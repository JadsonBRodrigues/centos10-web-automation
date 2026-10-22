# centos10-web-automation
Bash automation to install, secure and tune a CentOS Stream 10 web server

Automation of the installation, configuration, security, and optimization of a web server based on **CentOS Stream 10**, using Bash scripts. The server is designed to host a website accessible through a public IP address.

ATEC final project — UC00636. The goal is to reduce manual intervention and make the configuration process more reproducible on a fresh machine by running the scripts individually and in the defined order, from `script00` to `script14`.

> **Warning:** This project was developed for educational and laboratory purposes. Before using it on a production server, review all scripts, passwords, firewall rules, network settings, and recovery procedures. Do not publish real credentials in the repository.

## Features

| Area | Components and Tasks |
|---|---|
| Networking | Static IP configuration using `nmcli` (NetworkManager) |
| Web Server | Apache (`httpd`), PHP-FPM, and MariaDB |
| Security | `firewalld`, SELinux in enforcing mode, Fail2ban for SSH and Apache, ModSecurity with OWASP CRS |
| Alerts | Postfix configured to use Gmail as a relay, with centralized logging at `/var/log/seguranca.log` |
| Optimization | Apache, MariaDB, and PHP configuration tuning |
| Maintenance | Updates, daily backups, and monitoring tasks |
| Deployment | Script for website deployment |

## Requirements

- A clean installation of **CentOS Stream 10**.
- Administrative access to the virtual machine console; execution requires `root` privileges.
- An Internet connection.
- Git installed. If necessary, run `dnf install -y git`.
- For email alerts, a Gmail account with two-step verification enabled and an app password.
- To make the website accessible over the Internet, port forwarding for ports 80 and 443 on the router to the server's IP address. This configuration must be performed manually.

## Quick Start

Run the following commands in the **virtual machine console, not over SSH**, because the network configuration script may change the IP address and interrupt the remote connection.

```bash
sudo -i
dnf install -y git
git clone https://github.com/JadsonBRodrigues/centos10-web-automation.git /root/projeto-web
cd /root/projeto-web
chmod +x scripts/*.sh
```

### Run the Scripts in the Defined Order

Run each script individually, following the order below. Make sure each script completes successfully before proceeding to the next one.

```bash
./scripts/script00-prepare_f.sh
./scripts/script01-static-ip.sh
./scripts/script02-install-services.sh
./scripts/script03-secure-mariadb.sh
./scripts/script04-firewall.sh
./scripts/script05-selinux.sh
./scripts/script06-mail-relay.sh
./scripts/script07-fail2ban.sh
./scripts/script08-modsecurity.sh
./scripts/script09-apache-ssl-tuning.sh
./scripts/script10-mariadb-tuning.sh
./scripts/script11-php-tuning.sh
./scripts/script12-update-backup.sh
./scripts/script13-monitoring.sh
./scripts/script14-deploy-website.sh
```

The repository must be cloned to `/root/projeto-web` because the scripts expect to find the generated configuration files in that location.

The `script00-prepare_f.sh` script prompts for the IP address (including the subnet mask), gateway, and DNS servers. The `script06-mail-relay.sh` script prompts for the information required to configure the email relay.

## Network Configuration

Network parameters are requested by `script00-prepare_f.sh` during execution. The `project.conf` file is not used in this workflow.

The following example values can be used as a reference when preparing the configuration:

```bash
STATIC_IP="192.168.1.50/23"
STATIC_GATEWAY="192.168.1.1"
STATIC_DNS="1.1.1.1 8.8.8.8"
```

**Replace the example values with the correct parameters for your network before running the setup scripts.** Incorrect values may disrupt the machine's network connectivity.

Enter the appropriate values for your network when prompted by `script00-prepare_f.sh`. Do not copy the example values without verifying that they are correct for your environment.

The Gmail app password must not be stored in the repository or included in commits.

## Script Order and Description

| No. | Script | Description |
|---:|---|---|
| 00 | `script00-prepare_f.sh` | Prepares the project structure and generates `config.env` with network parameters |
| 01 | `script01-static-ip.sh` | Configures the static IP using `nmcli` and tests connectivity |
| 02 | `script02-install-services.sh` | Installs and enables Apache, PHP, and MariaDB; creates `info.php` and tests the website |
| 03 | `script03-secure-mariadb.sh` | Applies MariaDB security measures and creates the project's database and user |
| 04 | `script04-firewall.sh` | Configures `firewalld` to allow ports 22, 80, and 443 |
| 05 | `script05-selinux.sh` | Configures SELinux in enforcing mode, generates a `sealert` report, and creates the centralized log |
| 06 | `script06-mail-relay.sh` | Configures Postfix to send alerts through Gmail |
| 07 | `script07-fail2ban.sh` | Configures SSH and Apache protection, including bans after failed attempts and email alerts |
| 08 | `script08-modsecurity.sh` | Installs ModSecurity with OWASP CRS and runs simulated SQL injection and XSS tests |
| 09 | `script09-apache-ssl-tuning.sh` | Tunes the Apache configuration and configures SSL/TLS |
| 10 | `script10-mariadb-tuning.sh` | Applies configuration tuning to MariaDB |
| 11 | `script11-php-tuning.sh` | Applies configuration tuning to PHP |
| 12 | `script12-update-backup.sh` | Configures update tasks and daily backups |
| 13 | `script13-monitoring.sh` | Configures log reports, alerts, and time synchronization |
| 14 | `script14-deploy-website.sh` | Deploys the website |

## Manual NAT Configuration on the Router

**Mandatory step: after script 08 and before script 09.**

After completing `script08-modsecurity.sh` and before running `script09-apache-ssl-tuning.sh`, you must manually configure the NAT rules on the LAN router.

### Procedure

1. On a computer connected to the local area network (LAN), open a web browser.
2. Access the router's administration interface.
3. Navigate to **Access Control** in the router interface.
4. Create the two NAT rules.
5. Update both rules so that they point to the IP address of the virtual machine (VM) running the CentOS Stream 10 server.
6. Save the changes and verify that both rules point to the correct VM IP address.

**Once these steps are complete, you can proceed with `script09-apache-ssl-tuning.sh`.**

> **Note:** Verify the VM's current IP address before updating the rules. NAT configuration is manual and is not performed by the project scripts.

## Running an Individual Script

From the project directory, with `root` privileges, you can run a specific script:

```bash
cd /root/projeto-web
./scripts/script05-selinux.sh
```

Start with `script00-prepare_f.sh`, as it generates the `config.env` file used by subsequent scripts.

Run individual scripts only when you understand their dependencies and the current state of the server.

## Recovery After a Failure

### If a Script Fails

Check the error message, fix the underlying issue, and only then run the script again.

The `script03-secure-mariadb.sh` script may not be safe to rerun on an already configured installation because the database and user may already exist.

Rerun only the necessary script after identifying the cause of the failure and checking the effects of running it again. On a fresh installation, always start with `script00-prepare.sh`.

## Logs

| Path | Contents |
|---|---|
| `/var/log/seguranca.log` | Centralized security log, including events related to SELinux, email, Fail2ban, and ModSecurity |
| `logs/` | Directory for project logs, if generated by the scripts |
| `logs/sealert-*.txt` | SELinux reports |

## Security and Important Notes

- This project is run using individual scripts, from `script00-prepare_f.sh` to `script14-deploy-website.sh`, in the documented order. The workflow described in this README does not use `install.sh` or `project.conf`.
- On CentOS Stream 10, network configuration is managed through NetworkManager; this project uses `nmcli`.
- Router port forwarding must be configured manually and depends on the router hardware and Internet service provider.
- **Credentials:** Review the scripts before publishing or running the project. Remove any lab passwords hardcoded in the source code and use strong, unique credentials. If a real credential has already been published, change it immediately; deleting it in a subsequent commit does not necessarily remove it from Git history.
- **`info.php` file:** This file may expose information about the PHP environment. After testing, remove it using `rm /var/www/html/info.php` if it is no longer needed.
- **External access:** Verify that your Internet connection allows incoming connections and that the router forwards the required ports to the server. If your connection uses CGNAT, IPv4 port forwarding may not work without an additional solution provided by your ISP.
- **Production environments:** Before exposing the server to the Internet, validate firewall rules, updates, file permissions, TLS certificates, backups, and data recovery procedures.

## Repository Structure

```text
centos10-web-automation/
├── config.env          # Generated during preparation; must not be version-controlled
├── logs/
└── scripts/
    ├── script00-prepare_f.sh
    ├── script01-static-ip.sh
    ├── script02-install-services.sh
    ├── script03-secure-mariadb.sh
    ├── script04-firewall.sh
    ├── script05-selinux.sh
    ├── script06-mail-relay.sh
    ├── script07-fail2ban.sh
    ├── script08-modsecurity.sh
    ├── script09-apache-ssl-tuning.sh
    ├── script10-mariadb-tuning.sh
    ├── script11-php-tuning.sh
    ├── script12-update-backup.sh
    ├── script13-monitoring.sh
    └── script14-deploy-website.sh
```

---

**Academic Project:** ATEC — UC00636

**Repository:** [JadsonBRodrigues/centos10-web-automation](https://github.com/JadsonBRodrigues/centos10-web-automation)
