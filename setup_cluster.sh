#!/bin/bash
#set -x

echo "Reading benchmark configuration (benchmark.conf)."
source benchmark.conf

T_DIR="/home/$SUDOUSER"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "

# Setup Cassandra data nodes and pre-requisites
echo "--------------------------------"
echo "Setting up Cassandra data nodes."

IFS=":" read -r SEED_EIP SEED_IIP SEED_DPATH <<<"$CASSANDRA1"
echo "Seed node IP is $SEED_IIP"

# Copying test data over
for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
do
  IFS=":" read -r EIP IIP DPATH <<<"$NODE"
  echo "Copying files to $IIP"
  rsync 2>/dev/null -qrz -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' helpers $SUDOUSER@$IIP:$T_DIR
  rsync 2>/dev/null -qrz -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' tarballs/* $SUDOUSER@$IIP:$T_DIR
done

# Killing past deployments (if any)and removing files. This can replace the PD formatting after the first run.
echo "Checking for previous deployments."
for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
do
  IFS=":" read -r EIP IIP DPATH <<<"$NODE"
  $SSH 2>/dev/null $SUDOUSER@$IIP "sudo kill -9 \`ps -e | grep java | awk '{print \$1;}'\`"
  $SSH 2>/dev/null $SUDOUSER@$IIP "sudo rm -rf /tmp/*"
  $SSH 2>/dev/null $SUDOUSER@$IIP "sudo rm -rf /cassandra_data/*"
done
wait

# Formatting persistent disk. This can be commented out the second time you run the script.
for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
do
  IFS=":" read -r EIP IIP DPATH <<<"$NODE"
  echo "Mounting persistent disk on " $IIP
  $SSH $SUDOUSER@$IIP "$T_DIR/helpers/setup_data_folder.sh $DATA_FOLDER $DPATH" &
done
wait

# Make sure all Persistent disks are properly mounted
for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
do 
    IFS=":" read -r EIP IIP DPATH <<<"$NODE"
    MOUNT_POINT=`$SSH 2>/dev/null $SUDOUSER@$IIP "mount | grep $DATA_FOLDER | awk '{print $1}'"`
    if [ "" == "$MOUNT_POINT" ]
    then
	echo "Critical error. Failed to properly mount Persistent Disk at " $IIP
	exit
    fi
done

# This can be commented out the first run
for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
do
  IFS=":" read -r EIP IIP DPATH <<<"$NODE"
  echo "Setting Java up"
  $SSH $SUDOUSER@$IIP "$T_DIR/helpers/setup_java.sh $T_DIR"
done

# Starting the servers. Most servers successfully start even with this aggressive aproach (and a single seed instead of the advised 2).
for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
do
  IFS=":" read -r EIP IIP DPATH <<<"$NODE"
  echo "Setting Cassandra up"
  $SSH $SUDOUSER@$IIP "$T_DIR/helpers/setup_cassandra.sh $SEED_IIP $IIP $DATA_FOLDER $T_DIR" &
done
wait

# Copy data to the load generators
for NODE in `set | awk -F= '/LOAD_GENERATOR/ {print $2}'`
do
  echo "Copying files to $NODE"
  rsync 2>/dev/null -qrz -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' helpers $SUDOUSER@$NODE:$T_DIR
  rsync 2>/dev/null -qrz -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' tarballs/* $SUDOUSER@$NODE:$T_DIR
done

# Setup Java on load generators
for NODE in `set | awk -F= '/LOAD_GENERATOR/ {print $2}'`
do
  echo "Setting Java up"
  $SSH $SUDOUSER@$NODE "$T_DIR/helpers/setup_java.sh $T_DIR"
done

# Copy cassandra-stress to all load generators
for NODE in `set | awk -F= '/LOAD_GENERATOR/ {print $2}'`
do
  echo "Unpacking cassandra-stress on $EIP"
  $SSH $SUDOUSER@$NODE "tar -xzmf $T_DIR/dsc.tar.gz -C $T_DIR"
done

# Verify the cluster is up
echo "Waiting cluster to boostrap. (60 seconds)"
sleep 60
EXPECTED_NODES=`set | awk -F= '/CASSANDRA/ {print $2}' | wc -l`
ACTUAL_NODES=`$SSH 2>/dev/null $SUDOUSER@$SEED_IIP "$T_DIR/dsc-cassandra-2.0.8/bin/nodetool status | grep UN | wc -l"`
if [ "$EXPECTED_NODES" -ne "$ACTUAL_NODES" ]
then 
    echo "Expecting " $EXPECTED_NODES " data nodes, but only " $ACTUAL_NODES "are up. Will retry."
    for NODE in `set | awk -F= '/CASSANDRA/ {print $2}'`
    do 
	IFS=":" read -r EIP IIP DPATH <<<"$NODE"
	JAVA_PROCESS=`$SSH 2>/dev/null $SUDOUSER@$IIP "ps -e | grep java | awk '{print $1}'"`
	if [ "" == "$JAVA_PROCESS" ]
	then
	    echo "Retrying " $IIP
	    $SSH $SUDOUSER@$IIP "$T_DIR/helpers/setup_cassandra.sh $SEED_IIP $IIP $DATA_FOLDER $T_DIR"
	fi
    done
    echo "Waiting for retried nodes. (30 seconds)"
    sleep 30
fi

ACTUAL_NODES=`$SSH 2>/dev/null $SUDOUSER@$SEED_IIP "$T_DIR/dsc-cassandra-2.0.8/bin/nodetool status | grep UN | wc -l"`
if [ "$EXPECTED_NODES" -eq "$ACTUAL_NODES" ]
then 
    echo "Cluster ready."
else
    echo "Expecting " $EXPECTED_NODES " data nodes, but only " $ACTUAL_NODES "are up. Please validate manually."
fi

