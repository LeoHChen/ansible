# On-Demand upgrade Harmony Node using ansible playbook
This document provides a guidance on how to do on-demand upgrade of Harmony validator nodes using the ansible playbook provided in this repo.

## Why?
Currently, Harmony validator nodes can do auto-download, and auto-update, using a wrapper script, know as the `node.sh`.
However, auto-update is against the security and decentralization rule.
Any hijack of the central bucket may result in a fiasco of the blockchain network.
So, we will phrase out the auto-update function of the `node.sh`.
In the meantime, to ease the process of the node binary upgrade,
we provide an ansible playbook for validators to use for an on-demand upgrade process.

## Assumptions
The ansible playbook supports only Harmony node running with systemd service.
To get yourself familiar with systemd service, please check on this [document](https://www.freedesktop.org/software/systemd/man/systemd.service.html).
The current playbook was tested on AWS, GCP, Azure, DigitalOcean platforms.
If you are interested to have other platform support, please submit an issue or a PR to this repo.

### ansible
`ansible` is an open source community project sponsored by Red Hat.
It is simple and easy to start.
Many playbooks or documentation can be found in their [website](https://docs.ansible.com/ansible/latest/index.html).
You just need to have ssh access to your host/vps to manage the node using `ansible`.
The ansible client can run on Mac OS or Linux platform.

### ansible host file
Assuming you are running one validator node with IP address of `123.123.123.123`,
and the user name to login to the host is `ec2-user`.
The private key to access the host is saved in `~/.ssh/id_rsa`.
You may create the following inventory file in `/etc/ansible/hosts`.

```
[node]
123.123.123.123 ansible_user=ec2-user user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_rsa
```

If you have multiple nodes, you may also add them line by line into the `[node]` section of the file to manage them all at the same time.

### systemd service
There is a document on how to setup harmony node [using systemd with auto-update enabled](https://docs.harmony.one/home/validators/under-construction/installing-node/using-node.sh#3-setup-systemd).

Here is a sample of the `harmony.service` file that will be used for on-demand update.

Noted, we have disabled the auto-download and auto-update of harmony node as we need to manage the node upgrade process on-demand.
```
[Unit]
Description=Harmony Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
Restart=always
ExecStart=/home/ec2-user/node.sh -Sz -1D
StandardError=syslog
SyslogIdentifier=harmony
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
```

### disable auto-upgrade
Noted, the `-1D` option in node.sh specified in the above section will disable auto-download, and auto-update of the node binary.

### test connections
Test the connection of the ansible configuration.
```
# list all the vps/host configured under [node]
ansible node --list-hosts

# check the systemd service status
ansible node -a 'systemctl status harmony'
```

## On-demand Upgrade

### Release/Upgrade bucket
Harmony team maintains a few public release buckets containing the latest release of node.sh and node binary.
The most common one is the `main` bucket used for the latest public mainnet release.
The Harmony team uses the `upgrade` bucket for on-demand upgrade of internal nodes before the public release.

### Manual upgrade
Both the node.sh and node binary will be updated using the `upgrade-node.yml` playbook.

```bash
git clone https://github.com/harmony-one/ansible.git
cd ansible
ansible-playbook playbooks/upgrade-node.yml -e 'inventory=node upgrade=upgrade'
```
In this command, the `inventory` is the hostname or list.
The `upgrade` variable specifies the name of the bucket used in this upgrade process.

The `upgrade-node.yml` playbook will download the node binary and node.sh from the specified bucket.
And check/output the version of the binary.
If the binary version is the same as the current one, the upgrade won't be executed, unless you specified `force_update=true` in the command line option.

After the upgrade, the playbook will check the `BINGO` or `HOORAY` from the log file within 10 minutes to make sure the node can still join in the consensus.
You may also skip the checking using `skip_consensus_check=true` in the command line option.

For example, the following command skip the consensus check and do force update.
```bash
ansible-playbook playbooks/upgrade-node.yml -e 'inventory=node upgrade=upgrade force_update=true skip_consensus_check=true'
```

### Variables explained
* `inventory`: variable specify the inventory list. It can also be an IP address, or a list of hosts. They have to be configured in `/etc/ansible/hosts` file.
* `upgrade`: variable specify the name of the bucket. The bucket was maintained by Harmony team on AWS s3.
* `force_update`: boolean variable to indicate a force update progress even though the validator is running the same version, or the validator is currently a leader.
* `skip_consensus_check`: boolean variable to indicate the skip of consensus check after the upgrade. It can speed up the upgrade of a fleet of nodes, but use it in caution as it may break the entire fleet if any issues. Suggest testing the upgrade on one/two nodes before run it on a fleet of nodes.

### Revert to the previously released version
In case there is a failure to update the newer version, you may still revert back to the previous release.
```
ansible-playbook playbooks/upgrade-node.yml -e 'inventory=node upgrade=main force_update=true'
```
