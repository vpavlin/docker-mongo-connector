#!/bin/bash

mongo="${MONGO:-mongo}"
mongoport="${MONGOPORT:-27017}"
elasticsearch="${ELASTICSEARCH:-elasticsearch}"
elasticport="${ELASTICPORT:-9200}"


function _mongo() {
    mongo --quiet --host ${MONGO} <<EOF
    $@
EOF
}

res=-1

while [ ${res} -lt 0 ]; do
    res=$(_mongo "rs.initiate().ok")
    sleep 1
done
echo "Initiate returned: $res"
if [ "${res}" -ne 1 ]; then
    echo "ReplicaSet already configured, updating host info"

    mongo_host_port=$(_mongo "rs.config().members[0].host")
    mongo_host=${mongo_host_port%%:*}
    host=$(hostname)

    echo "Current host: $mongo_host, expected host: $host"

    if [ "${host}" != "${mongo_host}" ]; then
        res=$(_mongo "cfg = rs.config(); cfg.members[0].host='${host}:${mongo_host_port##*:}'; rs.reconfig(cfg, {force: true}).ok")
        if [ ${res} -ne 1 ]; then
            echo "Something went wrong - reconfig failed"
        else
            echo "Successfully reconfigured"
        fi
    fi
fi

is_master_result="false"
expected_result="true"

while true;
do
  if [ "${is_master_result}" != "${expected_result}" ] ; then
    is_master_result=$(_mongo "rs.isMaster().ismaster")
    echo "Waiting for Mongod node to assume primary status..."
    sleep 3
  else
    echo "Mongod node is now primary"
    break;
  fi
done

sleep 1

mongo-connector --auto-commit-interval=0 --oplog-ts=/data/oplog.ts -m ${mongo}:${mongoport} -t ${elasticsearch}:${elasticport} -d elastic_doc_manager
