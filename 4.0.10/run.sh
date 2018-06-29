#!/bin/bash

# Copyright 2018 The Kubernetes Authors.
# Modified by coder4
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function get_master_host() {
  master_name_upper=$(echo $1 | tr 'a-z' 'A-Z')
  master_host_var="REDIS_${master_name_upper}_MASTER_SERVICE_HOST"
  master_host=`eval echo '$'"$master_host_var"`
  echo $master_host
}

function get_master_port() {
  master_name_upper=$(echo $1 | tr 'a-z' 'A-Z')
  master_port_var="REDIS_${master_name_upper}_MASTER_SERVICE_PORT"
  master_port=`eval echo '$'"$master_port_var"`
  echo $master_port
}

function launchmaster() {
  if [[ ! -e /redis-master-data ]]; then
    echo "Redis master data doesn't exist, data won't be persistent!"
    mkdir /redis-master-data
  fi
  redis-server /redis-master/redis.conf --protected-mode no
}

function launchsentinel() {

  if [ x"$MASTER_NAME_LIST" == x"" ];then
    echo "env var MASTER_NAME_LIST invalid"
    exit 1
  fi

  sentinel_conf=sentinel.conf
  echo "# master config begin" > ${sentinel_conf}

  for master_name in $MASTER_NAME_LIST; do

    # config for current master name
    master_host=$(get_master_host $master_name)
    master_port=$(get_master_port $master_name)

    if [ x"$master_host" == x"" ];then
      echo "env var $master_name master host invalid"
      exit 1
    fi

    if [ x"$master_port" == x"" ];then
      echo "env var $master_name master port invalid"
      exit 1
    fi
    
    echo "# master config for ${master_name} begin" >> ${sentinel_conf}
    echo "sentinel monitor ${master_name} ${master_host} ${master_port} 2" >> ${sentinel_conf}
    echo "sentinel down-after-milliseconds ${master_name} 60000" >> ${sentinel_conf}
    echo "sentinel failover-timeout ${master_name} 180000" >> ${sentinel_conf}
    echo "sentinel parallel-syncs ${master_name} 1" >> ${sentinel_conf}
    echo "# master config for ${master_name} end" >> ${sentinel_conf}

  done

  echo "# master config end" >> ${sentinel_conf}
  echo "bind 0.0.0.0" >> ${sentinel_conf}

  redis-sentinel ${sentinel_conf} --protected-mode no
}

function launchslave() {
  # get MASTER_NAME
  if [[ x"$MASTER_NAME" == x"" ]]; then
    echo "Failed to find master-name"
    exit 1
  fi
  # get master's ip / port
  master_host=$(get_master_host $MASTER_NAME)
  master_port=$(get_master_port $MASTER_PORT)

  if [ x"$master_host" == x"" ];then
    echo "env var $master_name master host invalid"
    exit 1
  fi

  if [ x"$master_port" == x"" ];then
    echo "env var $master_name master port invalid"
    exit 1
  fi

  # try connect to master
  while true; do
    redis-cli -h ${master_host} -p ${master_port} INFO
    if [[ "$?" == "0" ]]; then
      break
     fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done

  sed -i "s/%master-ip%/${master_host}/" /redis-slave/redis.conf
  sed -i "s/%master-port%/${master_port}/" /redis-slave/redis.conf
  redis-server /redis-slave/redis.conf --protected-mode no
}

if [[ "${SENTINEL}" == "true" ]]; then
  launchsentinel
  exit 0
fi

if [[ "${MASTER}" == "true" ]]; then
  launchmaster
  exit 0
fi

if [[ "${SLAVE}" == "true" ]]; then
  launchslave
  exit 0
fi
