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


#  Out of box user experience
#    • install dependent packages (virsh, virt-install, etc.)
#    • download a qcow2 vm image and create cloud-init user/meta-data files
#    • clone this repository
#    • run sudo install.sh
#    • run nets builder for example_net
#    • create vm definition folder and yaml file (copy example_vm1)
#    • run virt-compose install example_vm1
#    • run virt-compose start example_vm1
#    • run virt-compose shutdown example_vm1
#    • run virt-compose undefine example_vm1

# To Do
#  [X] Update README.md with dependency information
#  [X] Update README.md with getting started steps
#  [ ] Update README.md with definition of the vm yaml file
#  [ ] Update README.md with libvirt auto-start/stop interactions
#  [ ] Script to install kvm packages (dependencies of installer?)
#  [ ] Script to build out networks from nets/* or just use virsh?
#  [X] Rename virt-compose.sh to just virt-compose
#  [X] Create installer
#       • Create /etc/virt-compose
#       • Install ./virt-compose.yaml /etc/virt-compose/virt-compose.yaml
#       • Install ./vm/* /etc/virt-compose/vm
#       • Install ./virt-compose /usr/bin
#
#  [X] Create Repository
#  [X] Code install
#  [X]  ** Update install to create systemd service
#  [X] Code undefine
#  [X]  ** Update to remove systemd service
#  [X] Code attach-device
#  [X] Code detach-device
#  [x] Code start
#  [X]  ** Update to create udev links
#  [X] Code start-all
#  [x] Code shutdown
#  [X]  ** Update to remove udev links
#  [X] Code shutdown-all

# Config bootstrap resolution
#   Config file full path; defaults to hardcoded value
#   Config file full path; can be overiden on comand line
#   All other config defaults to hardcoded values
#   All other config can be overidden in the config file GLOBAL map


# Global Variables
  BIN_FOLDER="/usr/bin"
  SYSTEMD_FOLDER="/etc/systemd/system"
  UDEV_RULES_FOLDER="/etc/udev/rules.d"
  QEMU_URI="qemu:///system"
  BASE_FOLDER="/etc/virt-compose"
  CONFIG="virt-compose.yaml"
  DOMAIN_METADATA_URI="http://stovenour.net/libvirt"
  DOMAIN_METADATA_NS="stovenour"

  VOLUME_PATH="/var/lib/libvirt/images"
  VM_FOLDER="vm"
  METADATA_FOLDER="cloud-init"
  SHUTDOWN_WAIT=120

#
# Install libvert VM and add udev hooks but don't start it
#
install() {
  echo >&2 "Info: install:  using VM definition: ${cfn_vm_def}"

  # Ensure domain does not exist; status should return error
  domain_running
  if [ $? -lt 2 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is already installed, not installing."
    return 1
  fi

  # Retrieve the bootDisk variables
  cfn_image_path=$(yq e '.bootDisk.imageLocation' $cfn_vm_def)
  if [ $? -ne 0 ] || [ -z "$cfn_image_path" ]; then
    echo >&2 "Error: Failed to read bootDisk/imageLocation in config: ${cfn_vm_def}"
    return 1
  fi
  cfn_boot_size=$(yq e '.bootDisk.size' $cfn_vm_def)
  if [ $? -ne 0 ] || [ -z "$cfn_boot_size" ]; then
    echo >&2 "Error: Failed to read bootDisk/size in config: ${cfn_vm_def}"
    return 1
  fi
  cfn_os_variant=$(yq e '.bootDisk.osVariant' $cfn_vm_def)
  if [ $? -ne 0 ] || [ -z "$cfn_os_variant" ]; then
    echo >&2 "Error: Failed to read bootDisk/osVariant in config: ${cfn_vm_def}"
    return 1
  fi

  # Create boot device
  echo >&2 "Info: Creating boot and metadata images in ${VOLUME_PATH}/${cfn_vm_name}"
  mkdir -vp ${VOLUME_PATH}/${cfn_vm_name}
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to make image folder: ${VOLUME_PATH}/${cfn_vm_name}"
    return 1
  fi

  # Make a copy of the image
  # TODO:  This assumes the input file is a qcow2 and no conversions are necessary
  echo >&2 "Info: Copying image from ${cfn_image_path}"
  cfn_boot_path=${VOLUME_PATH}/${cfn_vm_name}/${cfn_vm_name}.qcow2
  cp ${cfn_image_path} ${cfn_boot_path}
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to copy the image to the VOLUME_PATH: ${VOLUME_PATH}"
    return 1
  fi

  # Resize the image
  qemu-img resize ${cfn_boot_path} $cfn_boot_size
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to resize the image to ${boot_size}: ${cfn_boot_path}"
    return 1
  fi

  # Confirm that user-data and meta-data exist
  if [ ! -f "${cfn_vm_folder}/${METADATA_FOLDER}/meta-data" ]; then
    echo >&2 "Error: meta-data file missing from: ${cfn_vm_folder}/${METADATA_FOLDER}"
    return 1
  fi
  if [ ! -f "${cfn_vm_folder}/${METADATA_FOLDER}/user-data" ]; then
    echo >&2 "Error: user-data file missing from: ${cfn_vm_folder}/${METADATA_FOLDER}"
    return 1
  fi

  # Create the cloud-init cdrom iso
  pushd ${cfn_vm_folder}/${METADATA_FOLDER} > /dev/null
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to cd to: ${cfn_vm_folder}/${METADATA_FOLDER}"
    popd > /dev/null
    return 1
  fi

  cfn_cidata_path=${VOLUME_PATH}/${cfn_vm_name}/${cfn_vm_name}-cidata.iso
  sudo xorrisofs -o ${cfn_cidata_path} -V CIDATA -J -r * 2> /dev/null
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to run xorrisofs in folder: ${cfn_vm_folder}/${METADATA_FOLDER}"
    popd > /dev/null
    return 1
  fi
  popd > /dev/null

  # Array that will hold all the command line options for virt-install
  cfn_vm_parms=()

  # Define virt-install command parameters
  cfn_vm_parms+=("virt-install --import")
  cfn_vm_parms+=("--connect ${QEMU_URI}")
  cfn_vm_parms+=("--name ${cfn_vm_name}")
  cfn_vm_parms+=("--os-variant ${cfn_os_variant}")

  #   - include --disk for boot and cidata disks
  cfn_vm_parms+=("--disk ${cfn_boot_path},format=qcow2")
  cfn_vm_parms+=("--disk path=${cfn_cidata_path}")

  #   - include "--param value" for each entry in install.parameters[]
  cfn_install_params=$(yq e --output-format shell '.install.parameters[]' $cfn_vm_def)
  if [ $? -ne 0 ] || [ -z "$cfn_install_params" ]; then
    echo >&2 "Error: Failed to read install.parameters in config"
    return 1
  fi
  while IFS="=" read -r param value; do
    #echo "${param}-->${value}"
    cfn_vm_parms+=("--${param} ${value}")
  done <<< "${cfn_install_params//\'/}"  #remove single quotes from the shell format

  cfn_vm_parms+=("--noreboot") #don't start the VM

  # Call virt-install
  command_str=""
  for parm in "${cfn_vm_parms[@]}"; do
      #echo "${parm} \\"
      command_str+="${parm} "
  done
  command_str=${command_str::-1}
  echo >&2 $command_str

  (${command_str}) >> /dev/null
  if [ $? -ne 0 ]; then
    echo >&2 "Error: virt-installed failed"
    return 1
  fi
  echo >&2 ""

  # Create systemd service for USB host device hot-plug events
  #   NOTE:  vm name can not contain hyphen or systemd %j breaks
  local systemd_file="${SYSTEMD_FOLDER}/virt-compose-${cfn_vm_name}@.service"
  echo >&2 "Info: Creating systemd service: ${systemd_file}"
  cat << EOF | sudo tee ${systemd_file} >> /dev/null
[Unit]
Description=virt-compose: Manage device hot-plug event for %j@/%I

[Service]
Type=oneshot
SyslogIdentifier=%N
ExecStart=/bin/echo "Received vm: %j - device: /%I"
ExecStart=${BIN_FOLDER}/virt-compose --config ${BASE_FOLDER}/${CONFIG} attach-device %j /%I
EOF

  sudo systemctl daemon-reload

  return 0
}


#
# Set DEVNUM and DEVBUS variables for a device given 
#   the vendor id, product id, and serial number
# 
locate_device() {
  local vendor_id="$1"; local product_id="$2"; local serial_no="$3"
  local device
  local return_val=1  #assume failed

  for device in /sys/bus/usb/devices/*; do
    if [ -f "$device/idVendor" ] && [ -f "$device/idProduct" ]; then
      local device_vendor_id=$(cat "$device/idVendor")
      local device_product_id=$(cat "$device/idProduct")
      if [ "$device_vendor_id" == "$vendor_id" ] && [ "$device_product_id" == "$product_id" ]; then
        if [ -f "$device/serial" ]; then
          local device_serial_number=$(cat "$device/serial")
          if [ "$device_serial_number" == "$serial_no" ]; then
            #set DEVBUS and DEVNUM variables
            local udevadmOut=$(udevadm info -x --query=property ${device} | grep BUSNUM)
            local devbus_status=$?
            local value
            IFS="=" read -r param value <<< ${udevadmOut//\'/}
            DEVBUS=$value
            udevadmOut=$(udevadm info -x --query=property ${device} | grep DEVNUM)
            local devnum_status=$?
            IFS="=" read -r param value <<< ${udevadmOut//\'/}
            DEVNUM=$value
            return_val=$(( devbus_status && devnum_status ))
            if [ $return_val ]; then
              echo >&2 "Info: Found device $device, DEVBUS=${DEVBUS}, DEVNUM=${DEVNUM}"
            fi
          fi
        fi
      fi
    fi
  done
  return $return_val
}


#
# Returns a device id used as an index key in the metadata
# This function ensures all parts of the code format the same
#
gen_device_id() {
  local vendor="$1"; local product="$2"; local serial="$3"
  echo "usb-${vendor}-${product}-${serial}"
}


#
# Returns true(0) if the domain is running, false(1) if shutdown, and false(2) on error
#
domain_running() {

  local domain_status=$(virsh --connect ${QEMU_URI} domstate ${cfn_vm_name} 2> /dev/null)
  if [ $? -ne 0 ] || [ -z "${domain_status}" ]; then
    # echo >&2 "Error: Failed to get domain status for ${cfn_vm_name}"
    return 2
  fi

  if [ "$domain_status" == "running" ]; then
    #echo >&2 "Info: Domain is running for ${cfn_vm_name}"
    return 0
  #else
    #echo >&2 "Info: Domain is not running for ${cfn_vm_name}"
  fi

  return 1
}


#
# Writes metadata to --config if domain is shutdown and both --live and --config otherwise
#
metadata_write() {
  local new_metadata=$1

  local metadata_type="--config"

  domain_running
  local domain_status=$?
  if [ $domain_status -eq 0 ]; then
    metadata_type+=" --live"
  else
    if [ $domain_status -gt 1 ]; then
      return 1  #domain doesn't exist or some other error
    fi
  fi

  # Write new_metadata back to VM domain
  virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${metadata_type} ${DOMAIN_METADATA_URI} ${DOMAIN_METADATA_NS} "${new_metadata}" > /dev/null
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to write metadata for domain ${cfn_vm_name}"
    return 1
  fi

  return 0
}


#
# Retrieves all existing device metadata.  Patches the XML with new data for key.  
#   Rewrites the domain metadata.
#
metadata_add_device() {
  local key="$1"; local devbus="$2"; local devnum="$3"
  #echo "debug: metadata_add_device( key=${key}, devbus=${devbus}, devnum=${devnum})"
  local return_val=0 #assume return true

  local new_metadata='<usbdev>'

  # Retrieve metadata from VM domain
  local domain_metadata=$(virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI} 2> /dev/null)

  if [ ! -z "$domain_metadata" ]; then
    # Retrieve metadata keys
    local domain_keys=$(yq -p=xml '.usbdev.usb |= ([] + .) | .usbdev.usb | keys[]' <<< $domain_metadata)
    if [ $? -ne 0 ]; then
      echo >&2 "Error: Failed to retrieve keys from domian data for domain ${cfn_vm_name}"
      return 1
    fi
    #echo "domain_metadata='${domain_metadata}'"
    # Loop over all existing metadata keys saving the existing entries
    if [ ! -z "${domain_keys}" ]; then
      while IFS= read -r i; do
        #echo "Debug: Processing index: $i"
        # - Parse device data
        local domain_device=$(yq -p=xml  ".usbdev.usb |= ([] + .) | .usbdev.usb[$i] | .+@id + \" \" + .+@bus + \" \" + .+@device" <<< $domain_metadata)
        #echo "Debug: domain_device='${domain_device}'"
        # - Add existing entry to new_metadata structure #i.e. save all existing entries
        #   usb-0403_6001_FTF50XXM 002 036
        read -r id bus device <<< ${domain_device//\"/}  #remove quotes from items
        #echo "Debug: Parsed:  id=$id bus=$bus device=$device"
        #   "<usb id='0403_6001_FTF50XXM' bus='002' device='036'/>"
        new_metadata+="<usb id='${id}' bus='${bus}' device='${device}'/>"
      done <<< "${domain_keys}"
    fi
  fi

  # Add new device
  new_metadata+="<usb id='${key}' bus='${devbus}' device='${devnum}'/>"
  new_metadata+='</usbdev>'
  #echo "Debug: new_metadata=${new_metadata}"

  # Write new_metadata back to VM domain
  metadata_write "${new_metadata}"
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to write metadata for domain ${cfn_vm_name}"
    return_val=1
  fi

  return $return_val
}

#
# Retrieves all metadata, picks out XML matching $key; setting DEVBUS/DEVNUM
#   Removes device from metadata and rewrites the metadata
#
metadata_remove_device() {
  local key="$1"

  local return_val=1 #return false if entry is not found

  # Variables should be undefined if entry is not found in metadata
  unset DEVNUM
  unset DEVBUS

  # Retrieve metadata from VM domain
  local domain_metadata=$(virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI} 2> /dev/null)

  if [ -z "$domain_metadata" ]; then
    return_val=1
  else
    #echo "Looking for key: ${key}"
    local new_metadata='<usbdev>'

    # Retrieve metadata keys
    local domain_keys=$(yq -p=xml '.usbdev.usb |= ([] + .) | .usbdev.usb | keys[]' <<< $domain_metadata)
    if [ $? -ne 0 ]; then
      echo >&2 "Error: Failed to retrieve keys from domain data for domain ${cfn_vm_name}"
      return 1
    fi
    #echo "domain_metadata='${domain_metadata}'"
    # Loop over all existing metadata keys saving the entries that don't match
    local device_index
    if [ ! -z "${domain_keys}" ]; then
      while IFS= read -r device_index; do
        #echo "Processing index: $device_index"
        # - Retrieve device data
        local domain_device=$(yq -p=xml  ".usbdev.usb |= ([] + .) | .usbdev.usb[$device_index] | .+@id + \" \" + .+@bus + \" \" + .+@device" <<< $domain_metadata)
        #echo "domain_device='${domain_device}'"
        #   0403_6001_FTF50XXM 002 036
        read -r id bus device <<< ${domain_device//\"/}  #remove quotes from items
        #echo "Parsed:  id=$id bus=$bus device=$device"

        if [ "$key" == "$id" ]; then
          DEVBUS=$bus
          DEVNUM=$device
          return_val=0  #found so return true
        else
          # - Add existing entry to new_metadata structure #i.e. save all existing entries
          #   "<usb id='0403_6001_FTF50XXM' bus='002' device='036'/>"
          new_metadata+="<usb id='${id}' bus='${bus}' device='${device}'/>"
        fi

      done <<< "${domain_keys}"
    fi

    new_metadata+='</usbdev>'
    #echo $new_metadata

    # Write new_metadata back to VM domain
    metadata_write "${new_metadata}"
    if [ $? -ne 0 ]; then
      echo >&2 "Error: Failed to write metadata for domain ${cfn_vm_name}"
      return_val=1
    fi
  fi

  return $return_val
}


gen_device_xml() {
  local devbus="$((10#$1))"; local devnum="$((10#$2))"  #convert strings with leading zeros to base10 ints
  cat <<EOF
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <address bus='${devbus}' device='${devnum}' />
  </source>
</hostdev>
EOF
}


#
# Loop over all entries in vm state (metadata)
#   - If entry not already "visited"; then call detach-device and remove metadata
#
metadata_clean_devices() {
  # function parameters are a space separated list of visited device ids

  local return_val=0

  #Loop over the devices as function arguments populating an assciative array for doing key lookups
  declare -A visited_devices
  local visited_key=""
  if [ ! -z "$1" ]; then
    for visited_key in "$@"; do
      #echo "visited_devices[$visited_key]"
      visited_devices["${visited_key}"]="true"
    done
  fi

  # Loop over all entries in vm state (metadata)
  #   - If entry not already "visited"; then call detach-device and remove metadata

  # Retrieve metadata from VM domain
  local domain_metadata=$(virsh --connect ${QEMU_URI} metadata ${cfn_vm_name} ${DOMAIN_METADATA_URI} 2> /dev/null)

  if [ ! -z "$domain_metadata" ]; then
    local new_metadata='<usbdev>'

    # Retrieve metadata keys
    local domain_keys=$(yq -p=xml '.usbdev.usb |= ([] + .) | .usbdev.usb | keys[]' <<< $domain_metadata)
    if [ $? -ne 0 ]; then
      echo >&2 "Error: Failed to retrieve keys from domian data for domain ${cfn_vm_name}"
      return 1
    fi
    #echo "domain_metadata='${domain_metadata}'"
    # Loop over all existing metadata keys saving the entries that are not in visited_devices
    local device_index
    if [ ! -z "${domain_keys}" ]; then
      while IFS= read -r dev_index; do
        #echo "Processing index: $dev_index"
        # - Parse device data
        local domain_device=$(yq -p=xml  ".usbdev.usb |= ([] + .) | .usbdev.usb[$dev_index] | .+@id + \" \" + .+@bus + \" \" + .+@device" <<< $domain_metadata)
        #echo "domain_device='${domain_device}'"
        #   usb-0403_6001_FTF50XXM 002 036
        local device_id; local devbus; local devnum
        read -r device_id devbus devnum <<< ${domain_device//\"/}  #remove quotes from items
        #echo "Parsed:  id=$device_id bus=$devbus device=$devnum"

        #If found
        if [[ -v visited_devices["${device_id}"] ]]; then
          # save the metadata
          #echo "Device exists in visited_devices; saving: ${device_id}"
          new_metadata+="<usb id='${device_id}' bus='${devbus}' device='${devnum}'/>"
        else
          if [ ! -z "$device_id" ]; then
            # don't save metadata (i.e. delete from metadata)
            # call virsh detach-device
            echo >&2 "Info: Device not found in config; detaching from VM: ${device_id}"

            local old_device_xml=$(gen_device_xml $devbus $devnum)
            echo >&2 "Info: Running virsh detach-device ${cfn_vm_name} with bus=${devbus} device=${devnum}:"
            #echo $old_device_xml
            virsh --connect ${QEMU_URI} detach-device "${cfn_vm_name}" /dev/stdin --persistent <<< "$old_device_xml"
            if [ $? -ne 0 ]; then
              echo >&2 "Error: virsh detach-device failed for: ${device_id}"
            fi
          #else
            #echo "device_id is blank!; not saving... no other action taken"
          fi
        fi

        unset device
      done <<< "${domain_keys}"
    fi

    new_metadata+='</usbdev>'
    #echo "new_metadata=${new_metadata}"

    # Write new_metadata back to VM domain
    metadata_write "${new_metadata}"
    if [ $? -ne 0 ]; then
      echo >&2 "Error: Failed to write metadata for domain ${cfn_vm_name}"
      return_val=1
    fi
  fi

  return $return_val
}


#
# Start VM with virsh start $VM after detach/attach of USB devices
#
start() {
  echo >&2 "Info: start:  using VM definition: ${cfn_vm_def}"

  # Ensure domain exists but is not running
  domain_running
  local ret_val=$?
  if [ $ret_val -eq 0 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is already started."
    return 1
  elif [ $ret_val -gt 1 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is not installed, use install first."
    return 1
  fi

  local visited_devices=""

  # Loop through usbHostDev, if it exists, attaching the usb devices
  local usb_host_dev=$(yq e '.usbHostDev | keys[]' $cfn_vm_def 2> /dev/null)
  if [ $? -ne 0 ] || [ -z "$usb_host_dev" ]; then
    echo >&2 "Info: Did not find usbHostDev entries in config: ${cfn_vm_def}"
  else
    local dev_index
    local udev_rules=""
    while IFS= read -r dev_index; do
      # Query current bus/dev attachment for configured device
      local skip_device=0
      declare -A device

      local device_params=$(yq e ".usbHostDev[$dev_index] | to_entries[] | .key + \"=\" + .value" $cfn_vm_def)
      if [ $? -ne 0 ] || [ -z "$device_params" ]; then
        echo >&2 "Error: Failed to read usbHostDev list in config"
        skip_device=1
      else

        local key; local value
        while IFS="=" read -r key value; do
          #echo "${dev_index}: ${key}=${value}"
          device[${key}]=$value
        done <<< "${device_params}"

        #locate_device() sets DEVBUS and DEVNUM variables
        if ! locate_device ${device[vendor]} ${device[product]} ${device[serial]}; then
          skip_device=1
          echo >&2 "Warning:  Could not locate device -> name: ${device[name]}"
        fi
      fi

      if [ $skip_device -eq 0 ]; then
        local device_id=$(gen_device_id "${device[vendor]}" "${device[product]}" "${device[serial]}")
        local new_DEVNUM=$DEVNUM; local new_DEVBUS=$DEVBUS

        # TODO - if $DEVNUM eq $new_DEVNUM and $DEVBUS eq $new_DEVBUS, skip the detach/attach cycle

        # Call metadata_remove_device usb-vendor-product-serial to remove from metadata and return old bus/dev
        # sets $DEVNUM and $DEVBUS of the old attached device; unset if device not found
        metadata_remove_device $device_id
        if [ $? ]; then
          visited_devices+="${device_id} "
        fi

        #if dev is in metadata; Call virsh detach-device --persistent with old bus/dev to detach device
        if [ ! -z "$DEVNUM" ]; then
          local old_device_xml=$(gen_device_xml $DEVBUS $DEVNUM)
          echo >&2 "Info: Running virsh detach-device ${cfn_vm_name} with bus=${DEVBUS} device=${DEVNUM}:"
          #echo $old_device_xml
          virsh --connect ${QEMU_URI} detach-device "${cfn_vm_name}" /dev/stdin --persistent <<< "$old_device_xml"
          if [ $? -ne 0 ]; then
            echo >&2 "Error: virsh detach-device failed for: ${device_id}"
          fi
        fi

        # Call virsh attach-device --persistent with new bus/dev to attach device
        local new_device_xml=$(gen_device_xml $new_DEVBUS $new_DEVNUM)
        echo >&2 "Info: Running virsh attach-device ${cfn_vm_name} with bus=${new_DEVBUS} device=${new_DEVNUM}:"
        #echo $new_device_xml
        virsh --connect ${QEMU_URI} attach-device "${cfn_vm_name}" /dev/stdin --persistent <<< "$new_device_xml"
        if [ $? -ne 0 ]; then
          echo >&2 "Error: virsh attach-device failed for: ${device_id}"
        fi

        metadata_add_device $device_id $new_DEVBUS $new_DEVNUM

        # Create udev rule for the USB host device hot-plug event
        udev_rules+='ACTION=="add", SUBSYSTEM=="usb", DRIVER=="usb", '
        udev_rules+="ATTRS{idVendor}==\"${device[vendor]}\", "
        udev_rules+="ATTRS{idProduct}==\"${device[product]}\", "
        udev_rules+="ATTRS{serial}==\"${device[serial]}\", "
        udev_rules+='PROGRAM="/usr/bin/systemd-escape -p --template=virt-compose-example_vm1@.service $env{DEVNAME}", '
        udev_rules+='TAG+="systemd", ENV{SYSTEMD_WANTS}+="%c"'
        udev_rules+=$'\n'

      else
        echo >&2 "Warning:  Continuing without device"
      fi

      unset DEVNUM
      unset DEVBUS
      unset device

    done <<< "$usb_host_dev"
  fi

  #echo "udev_rules="$'\n'"$udev_rules"
  local udev_file="${UDEV_RULES_FOLDER}/90-virt-compose-${cfn_vm_name}.rules"
  echo >&2 "Info: Creating udev rules file: ${udev_file}"
  if [ ! -z "$udev_rules" ]; then
    cat << EOF | sudo tee ${udev_file} >> /dev/null
$udev_rules
EOF

    sudo udevadm control --reload-rules
  fi

  # Loop trough all devices in the metadata and remove any that were not in "visited"
  #   "visited" means the VM configuration exists and the device is present
  metadata_clean_devices $visited_devices  #intentionally left off "" to pass as a list of cmd parms

  # Damn...  finally, call virsh start
  virsh --connect ${QEMU_URI} start ${cfn_vm_name}
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to start ${cfn_vm_name}"
    return 1
  fi

  return 0
}


#
# systemd service uses this to start all the autoStart VMs on host boot
#
start_all() {
  echo >&2 "Info: start-all"

  local file
  for file in ${BASE_FOLDER}/${VM_FOLDER}/* ; do
    if [ -d "$file" ]; then
      cfn_vm_name=$(basename "${file}")
      cfn_vm_def="${file}/${cfn_vm_name}.yaml"
      echo >&2 "Info: Checking vm configuration: ${cfn_vm_def}"

      local auto_start=$(yq e '.autoStart' $cfn_vm_def)
      if [ $? -ne 0 ] || [ -z "$auto_start" ]; then
        echo >&2 "Error: Failed to read autoStart in config ${cfn_vm_def}. Skipping VM."
      elif [ "x$auto_start"="xtrue" ]; then
        echo >&2 "Info: Starting vm ${cfn_vm_name}"
        start || echo >&2 "Error: Failed to auto-start ${cfn_vm_name}"
      fi
    fi
  done

  return 0
}


#
# call virsh shutdown
#
shutdown() {
  echo >&2 "Info: shutdown:  using VM definition: ${cfn_vm_def}"

  # Ensure domain exists and is running
  domain_running
  local ret_val=$?
  if [ $ret_val -eq 1 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is already shutdown."
    return 1
  elif [ $ret_val -gt 1 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is not installed."
    return 1
  fi

  # Remove udev rules for USB host device hot-plug events
  local udev_file="${UDEV_RULES_FOLDER}/90-virt-compose-${cfn_vm_name}.rules"
  echo >&2 "Info: Removing udev rules file: ${udev_file}"
  sudo rm $udev_file
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to remove ${udev_file}"
  fi

  sudo udevadm control --reload-rules
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to reload udev rules"
  fi

  virsh --connect ${QEMU_URI} shutdown ${cfn_vm_name}
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to shutdown ${cfn_vm_name}"
    return 1
  fi
  return 0
}


#
# systemd service uses this to shutdown all VMs on host shutdown
#
shutdown_all() {
  echo >&2 "Info: shutdown-all"

  local wait_list=""
  local file
  for file in ${BASE_FOLDER}/${VM_FOLDER}/* ; do
    if [ -d "$file" ]; then
      cfn_vm_name=$(basename "${file}")
      cfn_vm_def="${file}/${cfn_vm_name}.yaml"
      echo >&2 "Info: Checking vm configuration: ${cfn_vm_def}"

      local auto_start=$(yq e '.autoStart' $cfn_vm_def)
      if [ $? -ne 0 ] || [ -z "$auto_start" ]; then
        echo >&2 "Error: Failed to read autoStart in config ${cfn_vm_def}. Skipping VM."
      elif [ "x$auto_start"="xtrue" ]; then
        echo >&2 "Info: Shutting down vm ${cfn_vm_name}"
        shutdown || echo >&2 "Error: Failed to shutdown ${cfn_vm_name}"
        wait_list+="${cfn_vm_name} "
      fi
    fi
  done

  local remaining_wait_list
  local timeout=$SHUTDOWN_WAIT
  if [ -n "$wait_list" ]; then
    echo >&2 "Info: Waiting for vms to shutdown. Timeout ${SHUTDOWN_WAIT} seconds."
    [ $timeout -lt 0 ] && timeout=0
    while [ -n "$wait_list" ] && [ $timeout -gt 0 ]; do
      remaining_wait_list=""
      for cfn_vm_name in $wait_list; do
        if ! domain_running; then
          echo >&2 "Info: Shutdown:  ${cfn_vm_name}"
        else
          remaining_wait_list+="${cfn_vm_name} "
        fi
      done
      wait_list=$remaining_wait_list
      if [ -n "$wait_list" ]; then
        sleep 1
        ((timeout--))
      fi
    done
  fi
  if [ -n "$wait_list" ]; then
    echo -n >&2 "Warning: Timeout reached. Remaining VMs:"
    for cfn_vm_name in $wait_list; do
      echo -n >&2 " ${cfn_vm_name}"
    done
    echo >&2
  fi

  return 0
}


#
# Wraps virsh attach-device and detach-device creating correct XML data
# Called by systemd service on udev hot-plug events
# Also can be called manually to add a device
#
attach_device() {
  echo >&2 "Info: attach-device device: ${cfn_device_path}"

  # Ensure domain exists
  domain_running
  if [ $? -gt 1 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is not installed."
    return 1
  fi

  local return_val=0

  # Use "udevadmin info $cfn_device_path" to retrieve ID_VENDOR_ID,
  #   ID_MODEL_ID, ID_SERIAL_SHORT, BUSNUM, and DEVNUM
  declare -A device

  local udevadmOut=$(udevadm info --export --query=env ${cfn_device_path})
  local udevadm_status=$?
  local param; local value

  if [ ! $udevadm_status ] || [ -z "$udevadmOut" ]; then
    echo >&2 "Error:  udevadm info failed for device ${cfn_device_path}"
  else
    #echo "udevadm command ok:  output: $udevadmOut"
    while IFS="=" read -r param value; do
      #echo "${dev_index}: ${param}=${value}"
      device[${param}]=$value
    done <<< ${udevadmOut//\'/}

    # Use $cfn_vm_name to remove the old device mapping matching vendor,
    #   product, serial from the vm metadata
    local device_id=$(gen_device_id "${device[ID_VENDOR_ID]}" "${device[ID_MODEL_ID]}" "${device[ID_SERIAL_SHORT]}")
    # Call metadata_remove_device usb-vendor-product-serial to remove from metadata and return old bus/dev
    # sets $DEVNUM and $DEVBUS of the old attached device; unset if device not found
    metadata_remove_device "${device_id}"
    if [ ! -z "$DEVNUM" ]; then
      local old_device_xml=$(gen_device_xml $DEVBUS $DEVNUM)
      echo >&2 "Info: Running virsh detach-device ${cfn_vm_name} with bus=${DEVBUS} device=${DEVNUM}:"
      #echo $old_device_xml
      virsh --connect ${QEMU_URI} detach-device "${cfn_vm_name}" /dev/stdin --persistent <<< "$old_device_xml"
      if [ $? -ne 0 ]; then
        echo >&2 "Error: virsh detach-device failed for: ${device_id}"
      fi

    fi

    # Use "virsh attach" to add the new device mapping
    local new_device_xml=$(gen_device_xml "${device[BUSNUM]}" "${device[DEVNUM]}")
    echo >&2 "Info: Running virsh attach-device ${cfn_vm_name} with bus=${device[BUSNUM]} device=${device[DEVNUM]}:"
    #echo $new_device_xml
    virsh --connect ${QEMU_URI} attach-device "${cfn_vm_name}" /dev/stdin --persistent <<< "$new_device_xml"
    if [ $? -ne 0 ]; then
      echo >&2 "Error: virsh attach-device failed for: ${device_id}"
    fi

    # Add new device mapping to metadata
    metadata_add_device $device_id ${device[BUSNUM]} ${device[DEVNUM]}

  fi

  unset device
  return $return_val
}


#
# Wraps virsh detach-device creating correct XML data
#
detach_device() {
  echo >&2 "Info: detach-device device: ${cfn_device_path}"

  # Ensure domain exists
  domain_running
  if [ $? -gt 1 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is not installed."
    return 1
  fi

  local return_val=0

  # Use "udevadmin info $cfn_device_path" to retrieve ID_VENDOR_ID,
  #   ID_MODEL_ID, ID_SERIAL_SHORT, BUSNUM, and DEVNUM
  declare -A device

  local udevadmOut=$(udevadm info --export --query=env ${cfn_device_path})
  local udevadm_status=$?
  local param; local value

  if [ ! $udevadm_status ] || [ -z "$udevadmOut" ]; then
    echo >&2 "Error:  udevadm info failed for device ${cfn_device_path}"
  else
    while IFS="=" read -r param value; do
      #echo "${dev_index}: ${param}=${value}"
      device[${param}]=$value
    done <<< ${udevadmOut//\'/}

    # Use $cfn_vm_name to remove the old device mapping matching vendor,
    #   product, serial from the vm metadata
    local device_id=$(gen_device_id "${device[ID_VENDOR_ID]}" "${device[ID_MODEL_ID]}" "${device[ID_SERIAL_SHORT]}")
    # Call metadata_remove_device usb-vendor-product-serial to remove from metadata and return old bus/dev
    # sets $DEVNUM and $DEVBUS of the old attached device; unset if device not found
    metadata_remove_device "${device_id}"
    if [ ! -z "$DEVNUM" ]; then
      local old_device_xml=$(gen_device_xml "${device[BUSNUM]}" "${device[DEVNUM]}")
      echo >&2 "Info: Running virsh detach-device ${cfn_vm_name} with bus=${device[BUSNUM]} device=${device[DEVNUM]}:"
      #echo $old_device_xml
      virsh --connect ${QEMU_URI} detach-device "${cfn_vm_name}" /dev/stdin --persistent <<< "$old_device_xml"
      if [ $? -ne 0 ]; then
        echo >&2 "Error: virsh detach-device failed for: ${device_id}"
      fi

    fi
  fi

  unset device
  return $return_val
}


#
# Undefines the VM, removes udev hooks, and removes the image folder
#
undefine() {
  echo >&2 "Info: uninstall:  using VM definition: ${cfn_vm_def}"

  # Ensure domain exists
  domain_running
  if [ $? -gt 1 ]; then
    echo >&2 "Error: VM ${cfn_vm_name} is not installed."
    return 1
  fi

  # Remove systemd service for USB host device hot-plug events
  local systemd_file="${SYSTEMD_FOLDER}/virt-compose-${cfn_vm_name}@.service"
  echo >&2 "Info: Removing systemd service: ${systemd_file}"
  sudo rm $systemd_file
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to remove ${systemd_file}"
  fi

  sudo systemctl daemon-reload
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to reload systemd after removing service"
  fi

  # virsh destroy - Hard immediate power off
  virsh --connect ${QEMU_URI} destroy ${cfn_vm_name} > /dev/null 2>&1
  # ignore error if not running
  # if [ $? -ne 0 ]; then
  #   echo >&2 "Error: Failed to destroy ${cfn_vm_name}"
  #   return 1
  # fi

  # virsh undefine - Remove VM definition
  virsh --connect ${QEMU_URI} undefine ${cfn_vm_name}
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to undefine ${cfn_vm_name}"
    return 1
  fi

  # Confirm that image folder exists and isn't root before trying to delete it
  local boot_path="${VOLUME_PATH}/${cfn_vm_name}"
  if [ -z "${VOLUME_PATH}" ]; then
    echo >&2 "Error: VOLUME_PATH is not defined; not deleting image folder"
    return 1
  fi
  if [ -z "${cfn_vm_name}" ]; then
    echo >&2 "Error: vm name is not defined; not deleting image folder"
    return 1
  fi
  if [ ! -d "${boot_path}" ]; then
    echo >&2 "Error: Image folder does not exist: ${boot_path}"
    return 1
  fi

  # remove the install files
  echo >&2 "Info: Removing VM boot volume: ${boot_path}"
  sudo rm -rf ${boot_path}
  if [ $? -ne 0 ]; then
    echo >&2 "Error: Failed to remove image folder: ${boot_path}"
    return 1
  fi

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

  Usage: $progname [-h|--help] [-c|--config] {action} [vm_name] [device_path]

  $progname is a script that mirrors lifecycle aspects of virsh and virt-install commands
  reading necessary inputs from a simple VM definition file in YAML.  It also dynamically
  manages USB host device passthrough with udev/systemd.

  Optional arguments:
    -h, --help          Show this help message and exit
    -c, --config        Specify full config file path
                          (default: ${BASE_FOLDER}/${CONFIG})
    [vm_name]           Unique name of the KVM VM (no hyphens)
    [device_path]       Specifies the device path for use with attach/detach

  Required arguments:
    {action}            install {vm_name}
                        start {vm_name}
                        start-all
                        shutdown {vm_name}
                        shutdown-all
                        attach-device {vm_name} {device_path}
                        detach-device {vm_name} {device_path}
                        undefine {vm_name}

HEREDOC
}


#
# main()
#

commands=("cat" "tee" "udevadm" "systemctl" "sudo" "yq" "qemu-img" "xorrisofs" "virsh" "virt-install")
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

if [[ $# -gt 3 ]]; then
    echo >&2 "ERROR: Too many arguments: $@"; usage; exit 1
fi
if [[ $# -gt 2 && ! "$1" =~ ^(attach-device|detach-device)$ ]]; then
    echo >&2 "ERROR: Too many arguments: $@"; usage; exit 1
fi
if [[ $# -gt 1 && "$1" =~ ^(start-all|shutdown-all)$ ]]; then
    echo >&2 "ERROR: Too many arguments: $@"; usage; exit 1
fi
if [[ $# -lt 1 ]]; then
    echo >&2 "ERROR: action is missing"; usage; exit 1
fi

if ! read_config; then exit 1; fi

cfn_vm_name=${2:-''}
# Check for presense of VM name parameter
if [[ -z "$cfn_vm_name" && ! "$1" =~ ^(start-all|shutdown-all)$ ]]; then
  echo >&2 "ERROR: vm_name is required for $1."; usage; exit 1
fi
# Ensure vm name does not conain a hyphen
if [[ "$cfn_vm_name" =~ "-" ]]; then
  echo >&2 "Error: VM name, ${cfn_vm_name}, must not contain a hyphen (-) due to systemd service parsing."
  exit 1;
fi
# Check for presense of VM folder and config file
cfn_vm_folder="${BASE_FOLDER}/${VM_FOLDER}"
cfn_vm_def=""
if [ ! -z "$cfn_vm_name" ]; then
  cfn_vm_folder="${BASE_FOLDER}/${VM_FOLDER}/${cfn_vm_name}"
  cfn_vm_def="${cfn_vm_folder}/${cfn_vm_name}.yaml"
  if [ ! -d "${cfn_vm_folder}" ]; then
    echo >&2 "Error: VM definition directory missing; expected: ${cfn_vm_folder}"; exit 1;
  fi
  if [ ! -f "${cfn_vm_def}" ]; then
    echo >&2 "Error: VM definition file missing; expected: ${cfn_vm_def}";  exit 1;
  fi
  echo >&2 "Info: Using VM folder: ${cfn_vm_folder}"
fi

case "${1:-''}" in
  'test')
    # do nothing
    ;;
  'install')
    install
    ;;
  'start')
    start
    ;;
  'start-all')
    start_all
    ;;
  'shutdown')
    shutdown
    ;;
  'shutdown-all')
    shutdown_all
    ;;
  'attach-device')
    cfn_device_path=${3:-''}
    if [ -z "$cfn_device_path" ]; then echo >&2 "ERROR: device path missing"; usage; exit 1; fi
    attach_device
    ;;
  'detach-device')
    cfn_device_path=${3:-''}
    if [ -z "$cfn_device_path" ]; then echo >&2 "ERROR: device path missing"; usage; exit 1; fi
    detach_device
    ;;
  'undefine')
    undefine
    ;;
  *) echo >&2 "ERROR: unrecognized action --> $1"; usage; exit 1 ;;
esac
