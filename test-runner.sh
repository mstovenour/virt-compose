#!/usr/bin/env bash

test_metadata_write() {
  echo "::::Starting metadata_write() tests::::"

  local new_metadata
  local result

  echo "Calling metadata_write() for $cfn_vm_name"
  new_metadata="<usbdev><usb id='usb-0403-6001-FTF50XXM' bus='002' device='055'/><usb id='usb-0403-6001-FTDPY3VD' bus='002' device='067'/></usbdev>"
  metadata_write "${new_metadata}"
  result=$?
  if [ $result -eq 0 ]; then
    echo "Metadata write success"
  else
    echo "Metadata write failure"
  fi

}

test_domain_running() {
  echo "::::Starting domain_running() tests::::"

  echo "Calling domain_running() for $cfn_vm_name"
  domain_running
  local ret_val=$?
  if [ $ret_val -eq 0 ]; then
    echo "domain is running"
  elif [ $ret_val -eq 1 ]; then
    echo "domain is shutdown"
  elif [ $ret_val -eq 2 ]; then
    echo "domain is undefined"
  else
    echo "undefined return value"
  fi

}

test_metadata_clean_devices() {
  echo "::::Starting metadata_clean_devices() tests::::"

  local visited_devices=""
  DEVID="usb-0403-6001-FTF50XXM"
  visited_devices+="${DEVID}"$'\n'
  DEVID="usb-0403-6001-FTDPY3VD"
  visited_devices+="${DEVID}"$'\n'

  echo "Calling metadata_clean_devices() with:"$'\n'"$visited_devices"
  metadata_clean_devices $visited_devices

  visited_devices=""
  echo "Calling metadata_clean_devices() with:"$'\n'"$visited_devices"
  metadata_clean_devices $visited_devices

}

test_read_device_config() {
  echo "::::Starting read_device_config() tests::::"

  # Loop through usbHostDev
  cfn_usb_host_dev=$(yq e '.usbHostDev | keys[]' $cfn_vm_def)
  if [ $? -ne 0 ] || [ -z "$cfn_usb_host_dev" ]; then
    echo >&2 "Error: Failed to read usbHostDev in config: ${cfn_vm_def}"
    return 1
  fi
  while IFS= read -r i; do
    if read_device_config $i; then
        echo "Found attached DEVID=${DEVID}, DEVBUS=${DEVBUS}, DEVNUM=${DEVNUM}"
    else
        echo "Not attached DEVID=${DEVID}"
    fi

    unset DEVID
    unset DEVBUS
    unset DEVNUM

  done <<< "$cfn_usb_host_dev"

}

test_metadata() {

  echo "::::Starting metadata_add_device() tests::::"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

  local devid="0403_6001_FTF50XXM"
  echo "Adding ${devid}"
  metadata_add_device "${devid}" "002" "036"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

  local devid="0403_6001_FTDPY3VD"
  echo "Adding ${devid}"
  metadata_add_device "${devid}" "002" "030"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

  local devid="0403_6001_FTDPY3ZZ"
  echo "Adding ${devid}"
  metadata_add_device "${devid}" "002" "032"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

  echo "::::Starting metadata_remove_device() tests::::"
  local devid="0403_6001_FTDPY3VD"
  echo "Removing ${devid}"
  metadata_remove_device "${devid}"
  echo "Removed bus=$DEVBUS, device=$DEVNUM"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

  devid="0403_6001_FTDPY3ZZ"
  echo "Removing ${devid}"
  metadata_remove_device "${devid}"
  echo "Removed bus=$DEVBUS, device=$DEVNUM"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

  devid="0403_6001_FTF50XXM"
  echo "Removing ${devid}"
  metadata_remove_device "${devid}"
  echo "Removed bus=$DEVBUS, device=$DEVNUM"
  echo "metadata now contains:"
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI}

}


source ./virt-compose.sh -c ./virt-compose-test.yaml test $1
# test_metadata
# test_read_device_config
# test_metadata_clean_devices
test_domain_running
#test_metadata_write
