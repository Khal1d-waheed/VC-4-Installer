# Crestron VC-4 Installation Bootstrap Wrapper

Crestron VC-4 Bootstrap Wrapper automates installation on RHEL, AlmaLinux, and Rocky. It handles OS checks, dependencies, SNMP config, license validation, and WebApp readiness, thus turning a manual, error-prone process into a stable one-command deployment.
This repository provides a **pure installer wrapper** for Crestron VC-4, designed to make installation focused, stable, and guess-free across supported Linux distributions.

---

## Why This Wrapper?

Installing Crestron VC-4 manually can be error-prone, time-consuming, and confusing, especially when dealing with strict OS requirements, dependency mismatches, license handling, and service readiness.

This wrapper was built to eliminate that pain by making the installation predictable, repeatable, and fully automated.

Here’s what sets it apart:

- *Aim* – The wrapper has a single mission: deploy VC-4. It doesn’t try to manage VMs, databases, or networking stacks. By staying laser-focused, it delivers a clean, reliable installation every time.

- *Stable & Controlled* – From the ground up, it enforces consistency and stability. The wrapper performs OS compatibility checks, installs required system packages, configures Python 3.9 with pinned dependencies, sets up SNMP, applies sysctl tuning, validates licensing, and ensures the WebApp is actually up and running before declaring success.

- *Purpose-Built Efficiency* – Every step is optimized to do one job well. It installs VC-4, verifies the environment, confirms health checks, and finally prints the exact access URL; no extra guesswork, no hidden surprises.

- *Zero Guesswork for the User* – Users no longer need to puzzle over which dependencies to install, where to place the Crestron installer, how to apply the license, or whether the WebApp is live. The wrapper automates all of it, turning what used to be a multi-step, error-prone process into a single streamlined command.

 **In short:** run one command and get a working VC-4 install
```bash
sudo ./bootstrap.sh
```
---
## Manual Install vs Wrapper Install

```
___________________________________________________________________________________________________________________________________________________________________
|      Functionality     |                 Manual Install (Without Wrapper)                   |               Wrapper Install (With bootstrap.sh)                 |
|------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------|
| OS Check               | User must read Crestron docs and ensure OS compatibility manually  | Auto-checks RHEL, AlmaLinux, Rocky versions before continuing     |
| Dependencies           | User installs each package individually, often missing versions    | Auto-installs all required system packages and pinned Python deps |
| Python Environment     | May conflict with system Python or wrong version                   | Creates isolated Python 3.9 venv with exact dependencies          |
| Conflicting Libraries  | Errors if old 32-bit libs exist                                    | Detects & removes conflicting libs automatically                  |
| Installer Handling     | User extracts and runs Crestron package manually                   | Auto-finds, extracts, copies to safe dir, and runs installVC4.sh  |
| SNMP Config            | Manual edits needed                                                | Auto-configured for VC-4 monitoring                               |
| License Application    | User must know where to place cert                                 | Prompted to paste or provide path, wrapper copies it correctly    |
| License Validation     | Manual curl or log check required                                  | Wrapper loops until status = VALID                                |
| WebApp Readiness       | User manually refreshes until it loads                             | Wrapper polls port/HTTP until backend is fully ready              |
| Final URL              | User guesses IP and port                                           | Wrapper prints final working URL confirmed with HTTP 200          |
| Reliability            | Inconsistent results, trial and error                              | Stable, repeatable, no guesswork                                  |
-------------------------------------------------------------------------------------------------------------------------------------------------------------------
```

## Supported Operating Systems

The wrapper has been validated on:

- RHEL 8.2+ / 9

- AlmaLinux 8.3+ / 9

- Rocky Linux 8.4+ / 9

Ubuntu and other distros are not supported by Crestron and are excluded here.

---

## Prerequisites

A supported Linux distribution (see above).

Root access (sudo).

Crestron VC-4 installer archive (.zip, .tar.gz, .tgz, or .tar).

---

## Folder Setup

Rename the folder as "VC4-Installer", where Crestron Installer as well as the bootstrap.sh file will be placed.
Clone or download this repository and place the Crestron installer archive in the same folder as bootstrap.sh:

```
VC-4 Installer/
├── bootstrap.sh
├── vc4-installer.zip   # <-- Downloaded from Crestron website
└── README.md
```

Rename the installer file if needed, but it must be in the same directory as the script.

---

## Installation

1- Open a terminal and navigate to the folder containing the VC-4 installer and the bootstrap.sh wrapper (the VC-4 Installer Folder).
``` 
cd ~/VC-4 Installer
```
2- Make the wrapper script executable: 
```
chmod +x bootstrap.sh
```
3- Run the wrapper as root:
```
sudo ./bootstrap.sh
```

The wrapper will:

- Validate OS version and root access.

- Install system prerequisites.

- Ensure Python 3.9 and pip.

- Create a clean Python venv.

- Install all Python dependencies (pinned versions).

- Extract and run Crestron’s installVC4.sh.

- Configure SNMP for VC-4 monitoring.

- Check license status:

- If missing or expired, you’ll be prompted:

- Provide a file path to the license, OR

- Paste the full license text (multi-line friendly; press Ctrl+D when finished, empty lines allowed).

- The wrapper will automatically re-check license status until it becomes VALID.

- Wait for the WebApp backend to be ready (up to 5 minutes).

- Print the final URL to access VC-4.

---

## License Handling

If no license is found, you’ll be prompted to provide one.

Two options are supported:

- Enter a file path (e.g. /home/user/cert.pem)

- Paste license text directly (press Ctrl+D when done, empty lines allowed)

The wrapper ensures the license is copied to the correct location and verifies it before continuing.

---

## Example Final Output

At the end of a successful install you’ll see:
```
=================================================
VC-4 Installation Completed Successfully
Logs saved to /var/log/vc4_wrapper.log
Access VC-4 via:→ http://<server-ip>/VirtualControl/config/settings/
=================================================
```
---

## Logs

All actions and errors are logged to:
```
/var/log/vc4_wrapper.log
```

Check this file for troubleshooting.

---

## Post-Install System Tuning

The wrapper applies Crestron-recommended sysctl networking settings automatically, but you can verify manually: 
```
cat /etc/sysctl.conf
```
Expected lines:
```
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_time=30
net.ipv4.tcp_retries2=8
```
To confirm they are live(gets printed in the Terminal automatically:
```
sysctl -p
sysctl net.ipv4.tcp_keepalive_intvl
sysctl net.ipv4.tcp_keepalive_time
sysctl net.ipv4.tcp_retries2
```
---

## Notes

- This wrapper does not bypass licensing requirements. A valid Crestron license is mandatory for production.

- Internet access is required to install dependencies.

- For enhanced security, it is strongly recommended to apply Crestron’s official Virtual Control hardening scripts (Answer ID: 1001249).
These scripts provide additional system hardening and align your deployment with Crestron’s best practices.

---

##  Quick Troubleshooting
-  WebApp not ready after 5 minutes

Cause: VC-4 service may be slow to start or failed during initialization.
Fix:
```
journalctl -u virtualcontrol.service -xe
systemctl restart virtualcontrol.service
```

Also ensure no conflicting processes are binding ports (e.g. 3030).


- License still invalid after paste/file

Cause: License may be expired, corrupted, or not properly applied.
Fix:
```
ls -l /opt/crestron/virtualcontrol/licenses/cert.0.pem
curl -s http://localhost:3030/api/license/status
```

If expired → request a new license from Crestron.

- Port not detected / blocked

Cause: Firewall may be blocking VC-4 ports.
Fix:
```
firewall-cmd --permanent --add-port=3030/tcp
firewall-cmd --reload
```
- Missing Python/Dependencies

Cause: OS repos may not provide Python 3.9 or required libs.
Fix:
```
dnf module enable python39
yum install -y python39 python39-pip python39-devel
```
---

## Contribution

Pull requests and improvements are welcome.
Please fork the repo and submit a PR.

---
