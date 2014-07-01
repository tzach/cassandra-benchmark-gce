#!/bin/bash
set -x

################################################################################
#
# Cassandra Cloud Benchmark
# Sets up storage for Cassandra data, logs and caches. Only PD is supported.
#
################################################################################

DATA_FOLDER=$1
DEVICE=$2

# Check if the data folder exists
has_lsof=`dpkg-query -W lsof 2>/dev/null`
if [ -z "$has_lsof" ] ; then
  sudo apt-get update
  sudo apt-get -f -q install lsof -y
fi

if [ -d /$DATA_FOLDER ]; then
  for p in `sudo lsof -t /$DATA_FOLDER`; do
    sudo kill -9 $p
  done
  sleep 20
  sudo umount -f /$DATA_FOLDER
  sudo rm -rf /$DATA_FOLDER
fi
sudo mkdir /$DATA_FOLDER
sudo mke2fs -F -F -O ^has_journal -t ext4 -b 4096 -E lazy_itable_init=0 $DEVICE
sudo mount $DEVICE /$DATA_FOLDER
sudo chmod a+w /$DATA_FOLDER
