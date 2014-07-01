#!/bin/bash
set -x

################################################################################
#
# Cassandra Cloud Benchmark
# Sets up Cassandra on the target node, including any environment change
#
################################################################################

# Cassandra SEED node - must bootstrap first
SEED_NODE=$1
ET0_ADDR=$2
STORAGE_PATH=$3
T_DIR=$4
CAS_DIR="$T_DIR/dsc-cassandra-2.0.8"
PID_FILE=cassandra_pid

echo "Unpacking Cassandra's tarball..."
tar -xzmf $T_DIR/dsc.tar.gz
sudo chmod 755 $CAS_DIR

echo "Configuring cassandra-env.sh..."
chmod +w $CAS_DIR/conf/cassandra-env.sh
cp $CAS_DIR/conf/cassandra-env.sh $T_DIR
cat $T_DIR/cassandra-env.sh | \
  sed -r "s/-Xss180k/-Xss256k/" | \
  sed -r "s/#MAX_HEAP_SIZE=\"4G\"/MAX_HEAP_SIZE=\"24G\"/" | \
  sed -r "s/#HEAP_NEWSIZE=\"800M\"/HEAP_NEWSIZE=\"600M\"/" | \
  sed -r "s/JVM_OPTS=\"$JVM_OPTS -ea\"/\#JVM_OPTS=\"$JVM_OPTS -ea\"/" | \
  sed -r "s/XX:SurvivorRatio=8/XX:SurvivorRatio=4/" | \
  sed -r "s/XX:CMSInitiatingOccupancyFraction=75/XX:CMSInitiatingOccupancyFraction=70/" > \
  $T_DIR/local_cassandra-env.sh

echo "JVM_OPTS=\"\$JVM_OPTS -XX:+AggressiveOpts\"" >> \
  $T_DIR/local_cassandra-env.sh
echo "JVM_OPTS=\"\$JVM_OPTS -XX:MaxDirectMemorySize=5g\"" >> \
  $T_DIR/local_cassandra-env.sh
echo "JVM_OPTS=\"\$JVM_OPTS -XX:+UseLargePages\"" >> \
  $T_DIR/local_cassandra-env.sh
echo "JVM_OPTS=\"\$JVM_OPTS -XX:TargetSurvivorRatio=50\"" >> \
  $T_DIR/local_cassandra-env.sh
echo "JVM_OPTS=\"\$JVM_OPTS -Djava.rmi.server.hostname=$ET0_ADDR\"" >> \
  $T_DIR/local_cassandra-env.sh
cp $T_DIR/local_cassandra-env.sh \
  $CAS_DIR/conf/cassandra-env.sh

echo "Generating cassandra.yaml..."
PROCESSOR_COUNT=`nproc`
CONCURRENT_WRITES=`expr $PROCESSOR_COUNT \* 8`
cat $T_DIR/helpers/cassandra.yaml | \
  sed -r "s/__CLUSTER_NAME__/cassandracloudbenchmark/" | \
  sed -r "s/__DATA_PATH__/\\/$STORAGE_PATH/" | \
  sed -r "s/__SEEDS__/$SEED_NODE/" | \
  sed -r "s/__CONCURRENT_WRITES__/$CONCURRENT_WRITES/" | \
  sed -r "s/__ET0_ADDR__/$ET0_ADDR/" \
  > $T_DIR/helpers/local_cassandra.yaml
cp $T_DIR/helpers/local_cassandra.yaml $CAS_DIR/conf/cassandra.yaml

if [ ! -f $CAS_DIR/lib/jna.jar ]; then
  echo "Adjusting the location of the JNA jar."
  sudo ln -s /usr/share/java/jna.jar $CAS_DIR/lib
fi

# Start Cassandra and capture the process IP
echo "Starting Cassandra..."
sudo nohup $CAS_DIR/bin/cassandra -p "$T_DIR/$PID_FILE" &

