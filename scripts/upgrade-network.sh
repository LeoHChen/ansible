#!/bin/bash

ME=$(basename "$0")

function usage() {
   cat<<-EOT
Usage: $ME [options] [actions]

Options:
   -s stride         stride for rolling upgrade (default: $stride)
   -n network        select network for action (valid: mainnet,lrtn,stn)
   -S shard          select shard for action
   -i list_of_ip     list of IP (delimiter is ,)

Actions:
   rolling           do rolling upgrade
   restart           do restart shard/network
   update            do force update
   menu              bring up menu (default)

Examples:
   $ME -s 3 -n mainnet rolling
   $ME -i 1.2.3.4,2.3.4.5 update

EOT
   exit 0
}

function network_menu() {
   local network=$(whiptail --title "Network Operation" --menu \
      "Choose a network" 25 78 16 \
      "MAIN" "Harmony Mainnet" \
      "LRTN" "Long Running Test Net" \
      "STN" "P2P Stress Test Net" 3>&1 1>&2 2>&3)

   echo "$network"
}

function action_menu() {
   local network=$1

   local action=$(whiptail --title "Network: $network" --radiolist \
      "Choose an operation" 20 78 4 \
      "Rolling" "Rolling Upgrade" OFF \
      "Restart" "Restart The Shard" OFF \
      "Update" "Force Update" OFF \
      "Exit" "Exit the Menu" ON 3>&1 1>&2 2>&3)

   echo "$action"
}

function input_ip_box() {
   local network=$1

   local ip=$(whiptail --title "Network: $network" --inputbox \
      "A list of IP addresses, delimited by ," 8 78 \
      3>&1 1>&2 2>&3)

   echo "$ip"
}

function mainnet_shard_menu() {
   local network=$1

   local shard=$(whiptail --title "Network: $network" --radiolist \
      "Choose one/all shards" 20 78 12 \
      "s0" "shard 0 nodes" OFF \
      "s1" "shard 1 nodes" OFF \
      "s2" "shard 2 nodes" OFF \
      "s3" "shard 3 nodes" OFF \
      "all" "all nodes" OFF \
      "s0_canary" "shard 0 canary nodes" OFF \
      "s1_canary" "shard 1 canary nodes" OFF \
      "s2_canary" "shard 2 canary nodes" OFF \
      "s3_canary" "shard 3 canary nodes" OFF \
      "canary" "all canary nodes" OFF \
      "ip" "manual input IP addresses" OFF 3>&1 1>&2 2>&3)

   echo "$shard"
}

function lrtn_shard_menu() {
   local network=$1

   local shard=$(whiptail --title "Network: $network" --radiolist \
      "Choose one/all shards" 20 78 6 \
      "lrtns0" "shard 0" OFF \
      "lrtns1" "shard 1" OFF \
      "lrtns2" "shard 2" OFF \
      "lrtns3" "shard 3" OFF \
      "ip" "manual input IP addresses" OFF 3>&1 1>&2 2>&3)

    echo "$shard"
}

function stn_shard_menu() {
   local network=$1

   local shard=$(whiptail --title "Network: $network" --radiolist \
      "Choose one/all shards" 20 78 6 \
      "p2ps0" "shard 0" OFF \
      "p2ps1" "shard 1" OFF
      "ip" "manual input IP addresses" OFF 3>&1 1>&2 2>&3)

   echo "$shard"
}

function do_rolling_upgrade() {
   local net=$1
   local shard=$2
   local ip=$3
   echo "${net}/$shard/$ip"
   ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 2 -e "inventory=${shard} stride=2 upgrade=${release}"
}

function do_restart_shard() {
   local net=$1
   local shard=$2
   local ip=$3
   echo "${net}/$shard/$ip"
}

function do_force_update() {
   local net=$1
   local shard=$2
   local ip=$3
   echo "${net}/$shard/$ip"
}

####### default value ######
stride=2

while getopts ":s:S:n:i:" opt; do
   case ${opt} in
      s) stride=${OPTARG} ;;
      S) shard=${OPTARG} ;;
      n) net=${OPTARG} ;;
      i) ip=${OPTARG} ;;
      *) usage ;;
   esac
done

shift $((OPTIND-1))

action=${1:-menu}
shift

case $action in
   rolling)
      do_rolling_upgrade "$net" "$shard" "$ip"
      exit 0
      ;;
   restart)
      do_restart_shard "$net" "$shard" "$ip"
      exit 0
      ;;
   update)
      do_force_update "$net" "$shard" "$ip"
      exit 0
      ;;
   menu)
      whiptail --title "Network Operation" --msgbox "Welcome to operation on Harmony Network!" 8 78
      ;;
   *) usage ;;
esac

### menu ###
unset net action ip

net=$(network_menu)
action=$(action_menu "$net")
case $action in
   Exit) exit ;;
esac

case ${net} in
   MAIN)
      shard=$(mainnet_shard_menu "$net")
      ;;
   LRTN)
      shard=$(lrtn_shard_menu "$net")
      ;;
   STN)
      shard=$(stn_shard_menu "$net")
      ;;
esac

case ${shard} in
   ip) ip=$(input_ip_box "$net")
   ;;
esac

case $action in
   Rolling) do_rolling_upgrade "$net" "$shard" "$ip" ;;
   Restart) do_restart_shard "$net" "$shard" "$ip" ;;
   Update) do_force_update "$net" "$shard" "$ip" ;;
   *) exit ;;
esac

exit

PS3="Press 4 to quit: "

select opt in rolling_upgrade restart force_upgrade quit; do
   case $opt in
      rolling_upgrade)
         read -p "The group (s{0..3}/s{0..3}_canary/canary): " shard
         read -p "The release bucket: " release
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 2 -e "inventory=${shard} stride=2 upgrade=${release}"
         echo "NOTED: the leader won't be upgraded. Please upgrade leader with force_update=true"
         ;;
      restart)
         read -p "The node group or node IP: " shard
         read -p "Number of nodes in one batch (1-50): " batch
         read -p "Skip checking of consensus (true/false): " skip
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/restart-node.yml -f $batch -e "inventory=${shard} stride=${batch} skip_consensus_check=${skip}"
         ;;
      force_upgrade)
         read -p "The group (s{0..3}/s{0..3}_canary/canary): " shard
         read -p "The release bucket: " release
         # force upgrade and no consensus check
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 50 -e "inventory=${shard} stride=50 upgrade=${release} force_update=true skip_consensus_check=true"
         ;;
      quit)
         break
         ;;
      *)
         echo "Invalid option: $REPLY"
         ;;
   esac
done
