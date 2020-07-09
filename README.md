# introduction
Ansible is the new tool we used for network operations.
All the host info used by ansible is in `/etc/ansible/hosts`
Please make sure you have the ssh agent running with the right mainnet keys before any ansible operation.

```bash
ssh-add -l
2048 SHA256:K9D3flNNlwei50Hz78PXubKNacmSQqxiTaQfHf92bP8 leochen@MBP15.local (RSA)
```

# install ansible
https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html

# install ansible roles
```bash
ansible-galaxy install charliemaiors.rclone_ansible
ansible-galaxy install ryandaniels.create_users

```
# role: create_users
https://github.com/ryandaniels/ansible-role-create-users

# what is ansible vault
https://docs.ansible.com/ansible/latest/user_guide/vault.html

# create users on users / test

* edit inventory/test.hosts file to use your own host IP
* make sure you have proper ssh setup to login to your own host

## on ankr host
```bash
cd ~/ansible
ansible-inventory --list -i inventory/test.hosts
ansible-playbook playbooks/create-users.yml --ask-vault-pass --extra-vars "inventory=h2 user=ec2-user" -i inventory/test.hosts
```

## on aws instance
```bash
cd ~/ansible
ansible-inventory --list -i inventory/hmy.hosts
ansible-playbook playbooks/users.yml --ask-vault-pass --extra-vars "inventory=devop" -i inventory/hmy.hosts
```
# network operation using ansible
```bash
./scripts/upgrade-network.sh -h
Usage: upgrade-network.sh [options] [actions]

Options:
   -s stride         stride for rolling upgrade (default: 2)
   -b batch          batch of nodes for restart (default: 60)
   -S shard          select shard for action
   -i list_of_ip     list of IP (delimiter is ,)
   -r release        release version for release (default: upgrade)
   -n                dryrun mode

Actions:
   rolling           do rolling upgrade
   restart           do restart shard/network
   update            do force update
   menu              bring up menu to do operation (default)

Examples:
   upgrade-network.sh -s 3 -S canary rolling
   upgrade-network.sh -i 1.2.3.4,2.3.4.5 update
```

## mainnet upgrade operation

All operations on mainnet have to be done on the mainnet devop machine, `devop.t.hmny.io`.

First, please build the expected harmony binary.
```bash
cd harmony
./scripts/go_executable_build.sh

export WHOAMI=upgrade
./scripts/go_executable_build.sh release
```

```bash
cd ~/ansible
./scripts/upgrade-network.sh
```

## testnet upgrade operation

All operations on testnet (LRTN/STN) have to be done on the testnet devop machine, `devop.hmny.io`.

First, please build the expected harmony binary.
```bash
cd harmony
./scripts/go_executable_build.sh

export WHOAMI=testnet
./scripts/go_executable_build.sh release
```

```bash
cd ~/ansible
./scripts/upgrade-network.sh
```
