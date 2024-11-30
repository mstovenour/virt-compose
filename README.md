<div id="top"></div>

<!--
*** This README.md is based on https://github.com/othneildrew/Best-README-Template
-->

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

This package is still under construction and not complete.  Please do not try to use it yet.  I will create a release tag and change this message once it is functional enough for reliable use.  I accumulated enough functionality that I needed to backup my local copy and so created this initial repository for that purpose.

<!-- OVERVIEW -->
## Overview

virt-compose is a script that mirrors lifecycle aspects of virsh and virt-install commands reading necessary inputs from a simple VM definition file in YAML.  It also dynamically manages USB host device passthrough with udev/systemd.

### Motivation
Needed small, simple system to manage the lifecycle of KVM VMs on a home lab server.  Something similar to the functionality that Docker Compose brings to containers.  There are fully functional systems already available for KVM, mostly as GUIs, but those have steep learning curves and rapidly evolving feature sets that create breaking functionality churn.  I just wanted something simple to remember that is too small to need rapidly evolving functionality (i.e. stable over time).  A system where consumers can know that backward compatibility is always maintained.  The system just needs a few features that are primarily motivated by the need to manage hot-plug events for USB host passthrough while managing the lifecycle of VMs.  Base requirements:
  * Manage USB host passthrough devices
  * Start VMs at host startup
  * Stop VMs at host shutdown
  * Build VMs from a templated config defining VMs

### Supported Actions
Actions read VM configuration from: `/etc/virt-compose/vm/{vm_name}/{vm_name}.yaml`
  * `install {vm_name}`
    - Calls: `virt-install`
    - This command will do all the things necessary to define the VM but does not start the VM.  There is more than you think (e.g. prepping the boot device, creating the cloud-init CDROM image, etc.)
    - Creates the udev rules for a listed USB host device hot-plug event
  * `start [-a|--all] [vm_name]`
    - Calls: `virsh attach-device`, `virsh start`
    - Wraps the virsh attach-device command, locating the IDs, creating the necessary XML file, etc.
    - Wraps the virsh start command
  * `shutdown [-a|--all] [vm_name]`
    - Calls: `virsh shutdown`, `virsh detach-device`
    - Wraps the virsh shutdown command
    - Wraps the virsh detach-device command, locating the IDs, creating the necessary XML file, etc.
  * `attach-device {vm_name} {$devpath}`
    - Calls: `virsh attach-device`
    - Wraps the virsh attach-device command, locating the IDs, creating the necessary XML file, etc.
    - Called by systemd when udev fires events for a USB host device hot-plug event
  * `detach-device {vm_name} {$devpath}`
    - Calls: `virsh detach-device`
    - Wraps the virsh detach-device command, locating the IDs, creating the necessary XML file, etc.
    - Called by systemd when udev fires events for a USB host device hot-plug event
  * `undefine {vm_name}`
    - Calls: `virsh undefine`
    - Removes udev rules for a listed USB host device hot-plug event
    - Will not allow undefine on VMs that are not shutdown first as a safety interlock
### Systemd Services
  * `virt-compose.service`
    On host startup, starts all VMs designated as auto-start.
    On host shutdown, stops all services, if the service is running
    Calls `virt-compose [start|shutdown] --all`
  * `virt-compose-{vm_name}@.service`
    Triggers attach / detach device when udev rules detect monitored devices
    Calls `virt-compose [attach-device | detach-device] {$VM} {$devpath}`

<!-- GETTING STARTED -->
## Getting Started

### Prerequisites
* one
* two

### Installation

1. Step 1
   ```sh
   some linux command
   ```
1. Step 2
   ```sh
   some linux command
   ```

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- USAGE EXAMPLES -->
## Usage

### `virt-compose`
   ```
  Paste the usage section here from the actual script
  ```


<p align="right">(<a href="#top">back to top</a>)</p>


<!-- ROADMAP -->
## Roadmap

- [x] Add vm management commands for VM lifecycle statages
- [x] Add usb device mount support
- [ ] Add "net" subcommands to build networks from ./nets definitions

See the [open issues](https://github.com/mstovenour/virt-compose/issues) for a list of proposed features (and known issues).

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement" but you may not find someone willing to write the code.

Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

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


<p align="right">(<a href="#top">back to top</a>)</p>
