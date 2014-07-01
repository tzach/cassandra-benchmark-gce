#!/bin/bash
#set -x

# Load behcmark configuration
source benchmark.conf

T_DIR="/home/$SUDOUSER"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "

# Settings for the cassandra-stress tool
CONS="quorum"
REPL="3"
#NKEYS="100000000"
#RETRIES="1000"
NKEYS="1000000"
RETRIES="100"
THREADS="600"
OUT="\$HOSTNAME.results"

# Gather data node addresses
NODES=`set | awk -F: '/CASSANDRA/ {print $2}' | sed ':a;$!{N;ba};s/\n/,/g'`

# Computing the stress command
STRESS_CMD="$T_DIR/dsc-cassandra-2.0.8/tools/bin/cassandra-stress"

# Create Keyspace
echo "Creating Keyspace"
`$STRESS_CMD --nodes $NODES --replication-factor $REPL --consistency-level $CONS --num-keys 1 > /dev/null`

# Wait for keyspace to propagate
sleep 30

# Prepare the actual test command
STRESS_CMD="$STRESS_CMD --file \"$T_DIR/$OUT\" --nodes $NODES "
STRESS_CMD="$STRESS_CMD --replication-factor $REPL --consistency-level $CONS"
STRESS_CMD="$STRESS_CMD --num-keys $NKEYS -K $RETRIES -t $THREADS"

# Run the test across all load generators
echo "Executing the benchmark"
for IP in `set | awk -F= '/LOAD_GENERATOR/ {print $2}'`
do
  $SSH $SUDOUSER@$IP "$STRESS_CMD" & 
done

echo "Tests are running. To watch for progress execute the following command."
echo "for i in {1..$1}; do ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null l-\$i \"tail -n 1 /home/`whoami`/*results\" ; done"
echo "This command prints the last line of the results file. From each loader."
echo "Once all results print END, the test is complete."
