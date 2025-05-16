<div id="top"></div>

<!--
*** This README.md is based on https://github.com/othneildrew/Best-README-Template
-->

Repository Link: https://github.com/mstovenour/virt-compose

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#overview">Overview</a>
      <ul>
        <li><a href="#motivation">Motivation</a></li>
        <li><a href="#supported-actions">Supported Actions</a></li>
        <li><a href="#systemd-services">Systemd Services</a></li>
      </ul>
    </li>
    <li><a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

<!-- STATUS -->
## Status

This package is still under construction.  This readme needs more work.  The script is feature complete for the initial feature set, tested, and deployeed in my home lab.  Tested on Debian 10 (soon Debian 12).  However this needs significant testing by others in a variety of uses.  I welcome new issue submissions and, ideally, pull requests with fixes.

<!-- OVERVIEW -->
## Overview

virt-compose is a script that mirrors lifecycle aspects of virsh and virt-install commands reading necessary inputs from a simple VM definition file in YAML.  It also dynamically manages USB host device passthrough with udev/systemd.

### Motivation
In needed a small, simple system to manage the lifecycle of KVM VMs on a home lab server.  Something similar to the functionality that Docker Compose brings to containers.  There are fully functional systems already available for KVM, mostly as GUIs, but those have steep learning curves and rapidly evolving feature sets that create breaking functionality churn.  I just wanted something simple to remember that is too small to need rapidly evolving functionality (i.e. stable over time).  A system where consumers can know that backward compatibility is always maintained.  The system just needs a few features that are primarily motivated by the need to manage hot-plug events for USB host passthrough while managing the lifecycle of VMs.  Base requirements:
  * Manage USB host passthrough devices
  * Start VMs at host startup
  * Stop VMs at host shutdown
  * Build VMs from a templated config defining VMs

### Supported Actions
Actions read VM configuration from: `/etc/virt-compose/vm/{vm_name}/{vm_name}.yaml`
  * `install {vm_name}`
    - Calls: `virt-install`
    - This command will do all the things necessary to define the VM but does not start the VM.  There is more than you think (e.g. prepping the boot device, creating the cloud-init CDROM image, etc.)
    - Creates the systemd service called by udev on USB host device hot-plug event
  * `start {vm_name}`
    - Calls: `virsh attach-device`, `virsh start`
    - Wraps the virsh attach-device command, locating the IDs, creating the necessary XML file, etc.
    - Wraps the virsh start command
    - Creates the udev rules for each defined USB host device hot-plug event
  * `start-all`
    - Calls: `start` for each VM definition where autoStart=true
  * `shutdown {vm_name}`
    - Calls: `virsh shutdown`, `virsh detach-device`
    - Wraps the virsh shutdown command
    - Deletes the udev rules for each defined USB host device hot-plug event
  * `shutdown-all`
    - Calls: `shutdown` for every VM definition where autoStart=true
  * `attach-device {vm_name} {$devpath}`
    - Calls: `virsh attach-device`
    - Wraps the virsh attach-device command, locating the IDs, creating the necessary XML file, etc.
    - Called by systemd when udev fires events for a USB host device hot-plug event
  * `detach-device {vm_name} {$devpath}`
    - Calls: `virsh detach-device`
    - Wraps the virsh detach-device command, locating the IDs, creating the necessary XML file, etc.
  * `undefine {vm_name}`
    - Calls: `virsh undefine`
    - Deletes the systemd service called by udev on USB host device hot-plug event
    - Will not allow undefine on VMs that are not shutdown first as a safety interlock
### Systemd Services
  * `virt-compose.service`
    On host startup, starts all VMs designated as auto-start.
    On host shutdown, stops all services, if the service is running
    Calls `virt-compose [start|shutdown] --all`
  * `virt-compose-{vm_name}@.service`
    Triggers attach USB host device when udev rules detect monitored devices
    Calls `virt-compose attach-device {$VM} {$devpath}`

<!-- GETTING STARTED -->
## Getting Started

### Prerequisites
* A Debian 10 or later system (systemd based distribution)
* A working qemu-kvm installation with virsh and virt-install
* sudo, yq, xorriso, qemu-utils

### Installation

1. Install yq manually if your package manager does not support yq
   ```sh
   sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
       -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
   ```

1. Install virt-compose from github
   ```sh
   git clone https://github.com/mstovenour/virt-compose.git virt-compose.git
   cd virt-compose.git
   ./install.sh --config ./virt-compose.yaml
   ```

1. Edit `/etc/virt-compose/vm/example_vm1/example_vm1.yaml`:

    - Update `imageLocation` for a Debian generic qcow2
    - Update `usbHostDev` for currently installed usb devices

   ```sh
   vi /etc/virt-compose/vm/example_vm1/example_vm1.yaml
   ```

1. Test the VM lifecycle
   ```sh
   virt-compose install example_vm1
   virt-compose start example_vm1
   virt-compose shutdown example_vm1
   virt-compose undefine example_vm1
   ```

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- USAGE EXAMPLES -->
## Usage

### `virt-compose`
   ```
  Usage: virt-compose [-h|--help] [-c|--config] {action} [vm_name] [device_path]

  virt-compose is a script that mirrors lifecycle aspects of virsh and virt-install commands
  reading necessary inputs from a simple VM definition file in YAML.  It also dynamically
  manages USB host device passthrough with udev/systemd.

  Optional arguments:
    -h, --help          Show this help message and exit
    -c, --config        Specify full config file path
                          (default: /etc/virt-compose/virt-compose.yaml)
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
  ```

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- ROADMAP -->
## Roadmap

See the [open issues](https://github.com/mstovenour/virt-compose/issues) for a list of proposed features (and known issues).

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement" but you may not find someone willing to write the code.

Don't forget to give the project a star! Thanks again!

1. Fork the Project on Github
1. Create a clone on your workspace (`git clone https://github.com/{your-user-name}/virt-compose.git`)
1. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
1. Code away and don't forget to TEST
1. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
1. Push the Branch to your Github repository (`git push origin feature/AmazingFeature`)
1. Open a Pull Request in Github

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- LICENSE -->
## License

Distributed under the Apache 2.0 License. See [`LICENSE`](../LICENSE) for more information.

**Copyright**

Copyright 2024 Michael Stovenour

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.


<p align="right">(<a href="#top">back to top</a>)</p>


<!-- CONTACT -->
## Contact

Project Link: [https://github.com/mstovenour/virt-compose](https://github.com/mstovenour/virt-compose)

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

This README.md is based on https://github.com/othneildrew/Best-README-Template

<p align="right">(<a href="#top">back to top</a>)</p>
