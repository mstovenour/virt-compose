#!/usr/bin/env bash

#  Copyright 2024 Michael Stovenour

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# Global Variables
  BASE_FOLDER="/etc/virt-compose"
  CONFIG="virt-compose.yaml"
  VM_FOLDER="vm"
  METADATA_FOLDER="cloud-init"
  BIN_FOLDER="/usr/bin"


#
# Reads GLOBAL section from ${cfn_config_file} and exports the map of variables
#
read_config() {
  echo >&2 "Info: Reading config file: ${cfn_config_file}"
  envVars=$(yq e -r '.GLOBAL | to_entries[] | .key + "=" + .value' \
            $cfn_config_file)
  if [ $? -ne 0 ] || [ -z "$envVars" ]; then
    echo >&2 "Error: Failed to read global config: ${cfn_config_file}"
    return 1
  fi

  while IFS= read -r envVar; do
    export $envVar
  done <<< "$envVars"

  return 0
}


#
# Dump usage to stdout
#
usage() {
  cat << HEREDOC

  Usage: $progname [-h|--help] [-c|--config]

  Installs files from the current directory into folders specified by the config file, if specified.
  If the config file is not specified default folders are used (${BIN_FOLDER} and ${BASE_FOLDER}).

  Optional arguments:
    -h, --help          Show this help message and exit
    -c, --config        Specify full config file path
                          (default: ${BASE_FOLDER}/${CONFIG})

HEREDOC
}


#
# main()
#

commands=("install")
command_check=0
for command in "${commands[@]}"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo >&2 "ERROR: Please install the $command command"
    command_check=1
  fi
done
[ $command_check -eq 0 ] || exit 1

cfn_config_file=${BASE_FOLDER}/${CONFIG}
progname=$(basename $0)
OPTIONS=hc:
LONGOPTS=help,config:
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$progname" -- "$@")
if [ $? != 0 ] ; then usage; exit 1 ; fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        -c|--config) cfn_config_file="$2"; shift 2 ;;
        -h|--help)   usage; exit 1 ;;
        --) shift;   break ;;
    esac
done

if ! read_config; then exit 1; fi

sudo install -o root -g root -m 755 -d ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/${METADATA_FOLDER}
sudo install -o root -g root -m 644 -t ${BASE_FOLDER} ${CONFIG}
sudo install -o root -g root -m 644 -t ${BASE_FOLDER}/${VM_FOLDER}/example_vm1 ${VM_FOLDER}/example_vm1/*
sudo install -o root -g root -m 640 -t ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/${METADATA_FOLDER} ${VM_FOLDER}/example_vm1/${METADATA_FOLDER}/*
sudo install -o root -g root -m 755 -T virt-compose.sh ${BIN_FOLDER}/virt-compose
