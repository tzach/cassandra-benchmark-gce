#!/bin/bash

#######################################################
## Cassandra benchmark script
## to use:
## 1  ./setup_cassandra --setup // will create all relevant server,
## install them and run the cassandra cluster
## 2 ./setup_cassandra --run // will run the benchmark
## 3 ./setup_cassandra --delete // will delete all instances and disk
##
## Base on implementation of Google Cassandra 1M test
## http://googlecloudplatform.blogspot.co.il/2014/03/cassandra-hits-one-million-writes-per-second-on-google-compute-engine.html
## 
## The script set up Cassandra cluster and loaders
## All Cassandra servers are named cas-x (x is a number)
## Loaders are l-x
## l-1 server is the anchor: scripts are upload to it, and the
## setup_cluster script is called from it.
##
## WARNING: the scripts assume these names, and assume all instances
## with these names are part of the benchmark! 
##
## The following changes has been made from Google version:
## - OpenJDK is used (not Oracle), and install at the guest (not
## download to host first)
## - Cassandra is download at the guest (not download to host first)
## - default server is n1-standard-16
## - Cassandra version used is 2.0.8 (TODO: this should be a parameter)
##
#######################################################

PARAM_CAS_TYPE="--cas-type"
PARAM_LOAD_TYPE="--load-type"
PARAM_CAS_NUM="--load-num"
PARAM_LOAD_NUM="--load-num"
PARAM_PROJECT="--project"
PARAM_DEL="--delete"
PARAM_RUN="--run"
PARAM_SETUP="--setup"
PARAM_HELP="--help"

#CAS_TYPE="n1-standard-1"
#LOAD_TYPE="n1-standard-1"
CAS_TYPE="n1-standard-16"
LOAD_TYPE="n1-standard-16"
CAS_NUM="3"
LOAD_NUM="1"
PROJECT="skilled-adapter-452"

CAS_SERVERS=""
LOAD_SERVERS=""

DELETE=0
SETUP=0
RUN=0

print_help() {
 cat <<HLPEND
 
 This script build and test a Cassandra benchmark on GCE
 $PARAM_HELP - print this help screen and exit
 $PARAM_SETUP - create the instances, install the software, run the cluster
 $PARAM_RUN - run the benchmark
 $PARAM_DEL - delete the instances
 
HLPEND
}



while test "$#" -ne 0
do
  case "$1" in
    "$PARAM_CAS_TYPE")
      CAS_TYPE=$2
      shift 2
      ;;
    "$PARAM_LOAD_TYPE")
      LOAD_TYPE=$2
      shift 2
      ;;
    "$PARAM_CAS_NUM")
      CAS_NUM=$2
      shift 2
      ;;
    "$PARAM_LOAD_NUM")
      LOAD_NUM=$2
      shift 2
      ;;
    "$PARAM_PROJECT")
      PROJECT=$2
      shift 2
      ;;

    "$PARAM_SETUP")
      DELETE=0
      SETUP=1
      RUN=0
      shift 1
      ;;   

    "$PARAM_DEL")
      DELETE=1
      SETUP=0
      RUN=0
      shift 1
      ;;   

    "$PARAM_RUN")
      RUN=1
      DELETE=0
      SETUP=0
      shift 1
      ;;   

   "$PARAM_HELP")
      print_help
      exit 0
      ;;
    
  esac
done

if test x"$DELETE" = x"1"; then
    echo "delete temp files"
    rm scripts.tgz
    rm benchmark.conf
    echo "Delete data nodes"
    gcutil deleteinstance --zone=us-central1-b `for ((i=1; i<=$CAS_NUM; i++)); do echo -n cas-$i " "; done` --force --delete_boot_pd
    echo "Delete data loaders"
    gcutil deleteinstance --zone=us-central1-b `for ((i=1; i<=$LOAD_NUM; i++)); do echo -n l-$i " "; done` --force --delete_boot_pd
    echo "Delete disks"
    gcutil deletedisk --zone=us-central1-b `for ((i=1; i<=$CAS_NUM; i++));do echo -n pd1t-$i " "; done` --force
fi

if test x"$SETUP" = x"1"; then
    echo "Start building Cassandra cluster of $CAS_NUM instances of type $CAS_TYPE, and $LOAD_NUM loader servers of type $LOAD_TYPE "
    gcloud config set project "$PROJECT"
    echo "create cassandra nodes disks"
    gcutil adddisk --zone=us-central1-b --wait_until_complete --size_gb=1000 `for ((i=1; i<=$CAS_NUM; i++)); do echo -n pd1t-$i " "; done`
    echo "add cassandra instances"
    gcutil addinstance --zone=us-central1-b --add_compute_key_to_project --auto_delete_boot_disk --automatic_restart --use_compute_key --wait_until_running --image=debian-7-wheezy-v20140408 --machine_type=$CAS_TYPE `for ((i=1; i<=$CAS_NUM; i++)); do echo -n cas-$i " "; done`
    echo "add loader instances"
    gcutil addinstance --zone=us-central1-b --add_compute_key_to_project --auto_delete_boot_disk --automatic_restart --use_compute_key --wait_until_running --image=debian-7-wheezy-v20140408 --machine_type=$LOAD_TYPE `for ((i=1; i<=$LOAD_NUM; i++)); do echo -n l-$i " "; done`
    echo "Attach the disks to data nodes"
    for ((i=1; i<=$CAS_NUM; i++)); do gcutil attachdisk --zone=us-central1-b --disk=pd1t-$i cas-$i; done

    echo "Authorize one of the loaders to ssh and rsync everywhere"
    echo -e "ssh-keygen -t rsa;\n;\n;\n;exit;" | gcutil ssh --zone=us-central1-b l-1 'bash -s'

    echo "Download the public key"
    gcutil pull --zone=us-central1-b l-1 /home/`whoami`/.ssh/id_rsa.pub l-1.id_rsa.pub
    
    echo "Upload the key to all other VMs"
    for ((i=1; i<=$LOAD_NUM; i++)); do gcutil push --zone=us-central1-b l-$i l-1.id_rsa.pub /home/`whoami`/.ssh/; done
    for ((i=1; i<=$CAS_NUM; i++)); do gcutil push --zone=us-central1-b cas-$i l-1.id_rsa.pub /home/`whoami`/.ssh/; done

    echo "Authorize l-1 to ssh into every VM in the project"
    CAS_SERVERS=$(gcutil listinstances | grep "| cas-" | awk '{print $10;}' | sed ':a;N;$!ba;s/\n/ /g')
    LOAD_SERVERS=$(gcutil listinstances | grep "| l-" | awk '{print $10;}' | sed ':a;N;$!ba;s/\n/ /g')

    echo "Authorize l-1 to ssh to Cassandra servers: $CAS_SERVERS"
    for vm in $CAS_SERVERS; do ssh -o UserKnownHostsFile=/dev/null -o CheckHostIP=no -o StrictHostKeyChecking=no -i /home/`whoami`/.ssh/google_compute_engine -A -p 22 `whoami`@$vm "cat /home/`whoami`/.ssh/l-1.id_rsa.pub >> /home/`whoami`/.ssh/authorized_keys" ; done

    echo "Authorize l-1 to ssh to all load servers: $LOAD_SERVERS"
    for vm in $LOAD_SERVERS; do ssh -o UserKnownHostsFile=/dev/null -o CheckHostIP=no -o StrictHostKeyChecking=no -i /home/`whoami`/.ssh/google_compute_engine -A -p 22 `whoami`@$vm "cat /home/`whoami`/.ssh/l-1.id_rsa.pub >> /home/`whoami`/.ssh/authorized_keys" ; done

    echo "Generate the cluster configuration file"
    echo SUDOUSER=\"`whoami`\" >benchmark.conf; echo DATA_FOLDER=\"cassandra_data\">>benchmark.conf ; for r in `gcutil 2>/dev/null listinstances --zone=us-central1-b | awk 'BEGIN {c=0; l=0;} /cas/ { print "CASSANDRA"++c"=\""$10":"$8":/dev/sdb\"";} /l\-[0-9]/ { print "LOAD_GENERATOR"++l"=\""$10"\""; }'`; do echo $r; done >> benchmark.conf

    echo "Upload all scripts to l-1"
    rm scripts.tgz
    tar czf scripts.tgz *
    gcutil push --zone=us-central1-b l-1 scripts.tgz /home/`whoami`

    echo "unzip the script file on l-1"
    echo -e "tar xzf scripts.tgz" |  gcutil ssh --zone=us-central1-b l-1 'bash -s'

    echo "download JVM and Cassandra to the machine"
    echo -e "./helpers/download_cassandra_jvm.sh" |  gcutil ssh --zone=us-central1-b l-1 'bash -s'

    echo "setup cluster"
    echo -e "./setup_cluster.sh" |  gcutil ssh --zone=us-central1-b l-1 'bash -s'
  
fi

if test x"$RUN" = x"1"; then
    echo -e "./inserts_test.sh $CAS_NUM" |  gcutil ssh --zone=us-central1-b l-1 'bash -s'
fi

echo "Done"
