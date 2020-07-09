#!/bin/bash

ME=$(basename "$0")

function usage() {
   cat<<-EOT
Usage: $ME [options] [actions]

Options:
   -s stride         stride for rolling upgrade (default: $STRIDE)
   -b batch          batch of nodes for restart (default: $BATCH)
   -n network        select network for action (valid: mainnet,lrtn,stn)
   -S shard          select shard for action
   -i list_of_ip     list of IP (delimiter is ,)
   -r release        release version for release (default: $RELEASE)

Actions:
   rolling           do rolling upgrade
   restart           do restart shard/network
   update            do force update
   menu              bring up menu to do operation (default)

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

   if [ -n "$network" ]; then
      echo "$network"
   else
      echo "Exit"
   fi
}

function action_menu() {
   local network=$1

   local action=$(whiptail --title "Network: $network" --menu \
      "Choose an operation" 25 78 16 \
      "Back" "Return to previous Menu" \
      "Rolling" "Rolling Upgrade" \
      "Restart" "Restart The Shard" \
      "Update" "Force Update" \
      "Exit" "Exit the Menu" 3>&1 1>&2 2>&3)

   if [ -n "$action" ]; then
      echo "$action"
   else
      echo "Exit"
   fi
}

function input_ip_box() {
   local title=$1
   local init=$2

   local ip=$(whiptail --title "$title" --inputbox \
      "A list of IP addresses, delimited by ','" 8 78 \
      "$init" 3>&1 1>&2 2>&3)

   if [ -n "$ip" ]; then
      echo "$ip"
   else
      echo "Exit"
   fi
}

# https://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function validate_ip_addresses() {
   OIFS=$IFS
   IFS=','
   read -a IPARR <<< "$1"
   IFS=$OIFS

   for (( n=0; n < ${#IPARR[*]}; n++ )); do
      if ! valid_ip "${IPARR[$n]}"; then
         return 1
      fi
   done

   return 0
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
      "canary" "all canary nodes" ON \
      "ip" "manual input IP addresses" OFF 3>&1 1>&2 2>&3)

   if [ -n "$shard" ]; then
      echo "$shard"
   else
      echo "Exit"
   fi
}

function lrtn_shard_menu() {
   local network=$1

   local shard=$(whiptail --title "Network: $network" --radiolist \
      "Choose one/all shards" 20 78 6 \
      "lrtns0" "shard 0" OFF \
      "lrtns1" "shard 1" OFF \
      "lrtns2" "shard 2" OFF \
      "lrtns3" "shard 3" OFF \
      "lrtn" "all shards" ON \
      "ip" "manual input IP addresses" OFF 3>&1 1>&2 2>&3)

   if [ -n "$shard" ]; then
      echo "$shard"
   else
      echo "Exit"
   fi
}

function stn_shard_menu() {
   local network=$1

   local shard=$(whiptail --title "Network: $network" --radiolist \
      "Choose one/all shards" 20 78 6 \
      "p2ps0" "shard 0" OFF \
      "p2ps1" "shard 1" OFF \
      "p2p" "all shards" ON \
      "ip" "manual input IP addresses" OFF 3>&1 1>&2 2>&3)

   if [ -n "$shard" ]; then
      echo "$shard"
   else
      echo "Exit"
   fi
}

function input_release_box() {
   local network=$1

   local rel=$(whiptail --title "Network: $network" --inputbox \
      "Input the release bucket" 8 78 \
      3>&1 1>&2 2>&3)

   echo "$rel"
}

function release_menu() {
   local title=$1
   local menu_tmp=/tmp/$(mktemp menu.XXXX)

   # assume the host has permission to list s3 bucket
   aws s3 ls s3://pub.harmony.one/release/linux-x86_64/ | grep PRE | grep -v 'PRE v' | awk ' { print $2 } ' | sed 's,\(.*\)/,\1 \1,' | tr '\n' ' ' > "$menu_tmp"

   readarray -t menus < "$menu_tmp"

   local release
   while [ -z "$release" ]; do
      release=$(whiptail --title "$title" --menu \
         "Choose release bucket on s3://pub.harmony.one/release/linux-x86_64/" 30 78 20 \
         ${menus[@]} \
         "input" "manual input release bucket" 3>&1 1>&2 2>&3)

      case $release in
         input) release=$(input_release_box "$network") ;;
      esac
   done

   rm -f "$menu_tmp"
   echo "$release"
}

function do_rolling_upgrade() {
   local inv=$1
   local release=$2

   echo ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f "$STRIDE" -e "inventory=${inv} stride=${STRIDE} upgrade=${release}"
   whiptail --title "Notice" --msgbox "The leader won't be upgraded automatically. Please upgrade leader with force update" 8 78
}

function do_restart_shard() {
   local inv=$1
   echo ANSIBLE_STRATEGY=free ansible-playbook playbooks/restart-node.yml -f "$BATCH" -e "inventory=${inv} stride=${BATCH} skip_consensus_check=true"
}

function do_force_update() {
   local inv=$1
   local release=$2

   echo ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f "$BATCH" -e "inventory=${inv} stride=${BATCH} upgrade=${release} force_update=true skip_consensus_check=true"
}

####### default value ######
STRIDE=2
BATCH=60
RELEASE=upgrade

while getopts ":s:S:n:i:r:b:" opt; do
   case ${opt} in
      s) STRIDE=${OPTARG} ;;
      S) shard=${OPTARG} ;;
      n) net=${OPTARG} ;;
      i) ip=${OPTARG} ;;
      r) RELEASE=${OPTARG} ;;
      b) BATCH=${OPTARG} ;;
      *) usage ;;
   esac
done

shift $((OPTIND-1))

action=${1:-menu}
shift

case $action in
   rolling)
      do_rolling_upgrade "$shard" "$RELEASE" "$ip"
      exit 0
      ;;
   restart)
      do_restart_shard "$shard" "$ip"
      exit 0
      ;;
   update)
      do_force_update "$shard" "$RELEASE" "$ip"
      exit 0
      ;;
   menu)
      whiptail --title "Network Operation" --msgbox "Welcome to operation on Harmony Network!" 8 78
      ;;
   *) usage ;;
esac

### menu ###
unset net action ip

while true; do
   net=$(network_menu)
   case $net in
      Exit) exit 0 ;;
   esac
   action=$(action_menu "$net")
   case $action in
      Exit) exit 0 ;;
      Back) continue ;;
      *) break ;;
   esac
done

case ${net} in
   MAIN)
      shard=$(mainnet_shard_menu "$net") ;;
   LRTN)
      shard=$(lrtn_shard_menu "$net") ;;
   STN)
      shard=$(stn_shard_menu "$net") ;;
esac

case ${shard} in
   Exit) exit 0 ;;
   ip) 
      ip=$(input_ip_box "Please Input IP addresses.")
      while true; do
         case $ip in
            Exit) exit 0 ;;
         esac
         ip=$(echo "$ip" | tr -d ' ')
         if validate_ip_addresses "$ip"; then
            break
         else
            ip=$(input_ip_box "Invalid IP address(es)." "$ip")
         fi
      done
      ;;
   *) ip="" ;;
esac

# for rolling update or force update, get the release bucket info
case $action in
   Rolling|Update) 
      release=$(release_menu "Network: $net") ;;
esac

if [ -z $ip ]; then
   IPARR=( $shard )
fi

# do action per ip or per group
for (( n=0; n < ${#IPARR[*]}; n++ )); do
   case $action in
      Rolling)
         do_rolling_upgrade "${IPARR[$n]}" "$release" ;;
      Restart)
         do_restart_shard "${IPARR[$n]}" ;;
      Update)
         do_force_update "${IPARR[$n]}" "$release" ;;
      *)
         exit 0
   esac
done
