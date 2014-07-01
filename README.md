cassandra-benchmark-gce
=======================

Setup and run a Cassandra benchmark on GCE

This script base on implementation of Google Cassandra 1M test
http://googlecloudplatform.blogspot.co.il/2014/03/cassandra-hits-one-million-writes-per-second-on-google-compute-engine.html
as describe here:
https://gist.github.com/ivansmf/6ec2197b69d1b7b26153


Use the script at your own risk!
The script is NOT a production tool.

WARNING: the scripts assume these names, and assume all instances
with these names are part of the benchmark

## Usage
./setup_cassandra.sh --help

## Results
$ gcutil ssh l-
l-1$ cat cat l-1.results

## How it works
The script set up Cassandra cluster and loaders
All Cassandra servers are named cas-x (x is a number)
Loaders names are l-x

l-1 server is the anchor: script are upload to it, cluster setup and
run is execute from it.

## Notes
The following changes has been made from original Google version:
- OpenJDK is used (not Oracle), and install at the guest (not
download to host first)
- Cassandra is download at the guest (not download to host first)
- default server is n1-standard-16
- Cassandra version used is 2.0.8 (TODO: this should be a parameter)
- The stress test parameters in insert_test.sh was updated (NKEYS is
  now only 1000000)
- by default script setup 3 Cassandra server and 1 load server (300, 30 in the original script)
  
