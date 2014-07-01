#!/bin/bash

################################################################################
#
# Cassandra Cloud Benchmark
#
################################################################################

T_DIR=$1

echo "apt-get update"
sudo apt-get update

#echo install java
sudo apt-get -y install openjdk-7-jre 

JAVA_VERSION=`java -version 2>&1 >/dev/null | grep version | awk '{print $3}'`
echo "Java version is $JAVA_VERSION"


# Get Java Native Access (JNA) if not installed
has_jna=`dpkg-query -W libjna-java 2>/dev/null`
if [ -z "$has_jna" ] ; then
    sudo apt-get -f -q install libjna-java -y
fi


