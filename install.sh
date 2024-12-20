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
  BIN_FOLDER="/usr/bin"
  SYSTEMD_FOLDER="/etc/systemd/system"
  BASE_FOLDER="/etc/virt-compose"
  CONFIG="virt-compose.yaml"
  VM_FOLDER="vm"
  METADATA_FOLDER="cloud-init"


install() {
  echo "Info: Installing config in: ${BASE_FOLDER}"
  sudo install -v -o root -g libvirt -m 775 -d ${BASE_FOLDER}
  sudo install -v -o root -g libvirt -m 775 -d ${BASE_FOLDER}/${VM_FOLDER}
  sudo install -v -o root -g libvirt -m 775 -d ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/
  sudo install -v -o root -g libvirt -m 775 -d ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/${METADATA_FOLDER}
  sudo install -v -o root -g libvirt -m 664 -t ${BASE_FOLDER} ${CONFIG}
  sudo install -v -o root -g libvirt -m 664 -t ${BASE_FOLDER}/${VM_FOLDER}/example_vm1 ${VM_FOLDER}/example_vm1/*
  sudo install -v -o root -g libvirt -m 660 -t ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/${METADATA_FOLDER} ${VM_FOLDER}/example_vm1/${METADATA_FOLDER}/*

  echo "Info: Installing command in: ${BIN_FOLDER}"
  sudo install -v -o root -g root -m 755 -d ${BIN_FOLDER}
  sudo install -v -o root -g root -m 755 -T virt-compose.sh ${BIN_FOLDER}/virt-compose

  echo "Info: Installing systemd service in: ${SYSTEMD_FOLDER}"
  sudo install -v -o root -g root -m 755 -d ${SYSTEMD_FOLDER}
  local systemd_file="${SYSTEMD_FOLDER}/virt-compose.service"
  echo >&2 "Info: Creating systemd service: ${systemd_file}"
  cat << EOF | sudo tee ${systemd_file} >> /dev/null
[Unit]
Description=virt-compose: Manage VM auto-start and auto-shutdown
Wants=libvirtd.service
After=network.target
After=time-sync.target
After=libvirtd.service
After=virt-guest-shutdown.target
Before=libvirt-guests.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/virt-compose --config /etc/virt-compose/virt-compose.yaml start-all
ExecStop=/usr/bin/virt-compose --config /etc/virt-compose/virt-compose.yaml shutdown-all

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to reload systemd after creating service"
  fi
  sudo systemctl enable virt-compose.service
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to enable systemd service"
  fi
  sudo systemctl start virt-compose.service
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to start systemd service"
  fi

  echo >&2 "Info: Install completed"

  return 0
}

uninstall() {
  echo "Info: Removing config from: ${BASE_FOLDER}"
  sudo rm ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/${METADATA_FOLDER}/*
  sudo rmdir ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/${METADATA_FOLDER}
  sudo rm ${BASE_FOLDER}/${VM_FOLDER}/example_vm1/*
  sudo rmdir ${BASE_FOLDER}/${VM_FOLDER}/example_vm1
  sudo rmdir --ignore-fail-on-non-empty ${BASE_FOLDER}/${VM_FOLDER}
  sudo rm ${BASE_FOLDER}/${CONFIG}
  sudo rmdir --ignore-fail-on-non-empty ${BASE_FOLDER}

  echo "Info: Removing command from: ${BIN_FOLDER}"
  sudo rm ${BIN_FOLDER}/virt-compose
  sudo rmdir --ignore-fail-on-non-empty ${BIN_FOLDER}

  echo "Info: Removing systemd service from: ${SYSTEMD_FOLDER}"
  sudo systemctl stop virt-compose.service
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to stop systemd service"
  fi
  sudo systemctl disable virt-compose.service
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to disable systemd service"
  fi

  local systemd_file="${SYSTEMD_FOLDER}/virt-compose.service"
  echo >&2 "Info: Removing systemd service: ${systemd_file}"
  sudo rm $systemd_file
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to remove ${systemd_file}"
  fi

  sudo systemctl daemon-reload
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to reload systemd after removing service"
  fi

  sudo rmdir --ignore-fail-on-non-empty ${SYSTEMD_FOLDER}

  echo >&2 "Info: Uninstall completed"

  return 0
}

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

  Usage: $progname [-h|--help] [-c|--config] [uninstall]

  Installs files from the current directory into folders specified by the config file, if specified.
  If the config file is not specified default folders are used (${BIN_FOLDER} and ${BASE_FOLDER}).

  Optional arguments:
    -h, --help          Show this help message and exit
    -c, --config        Specify full config file path
                          (default: ${BASE_FOLDER}/${CONFIG})
    [uninstall]         Will remove files previously installed

HEREDOC
}


#
# main()
#

commands=("install" "sudo" "yq")
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

if [ "x$1" = "xuninstall" ]; then
  uninstall
elif [ -z "$1" ]; then
  install
else
  echo >&2 "ERROR: unrecognized action --> $1"; usage; exit 1
fi

exit 0