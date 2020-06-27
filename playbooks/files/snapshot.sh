#!/bin/bash
# this script is used to create harmony db snapshot and upload to public s3 bucket
# this script uses rclone to sync db snapshot

set -uo pipefail

ME=$(basename $0)

#set -x

if [ "$(uname -s)" == "Darwin" ]; then
   TIMEOUT=gtimeout
else
   TIMEOUT=timeout
fi

default_verbose=false
default_network=ostn
default_bucket=pub.harmony.one
default_snapshot=latest
default_tag=validator

function logging
{
   echo $(date) : $@
   SECONDS=0
}

function errexit
{
   logging "$@ . Exiting ..."
   exit -1
}

function expense
{
   local step=$1
   local duration=$SECONDS
   logging $step took $(( $duration / 60 )) minutes and $(( $duration % 60 )) seconds
}

function verbose
{
   [ $VERBOSE ] && echo $@
}

function usage
{
   cat<<EOF
Usage: $ME [Options] Command

PREREQUSITES:
* amazon linux 2/ubuntu
* jq
* awscli
* rclone
   * curl https://rclone.org/install.sh | sudo bash

OPTIONS:
   -h                      print this help message
   -v                      verbose mode

   -t tag                  tag of the node
                           (default: $default_tag)
   -B bucket               specified bucket to upload
                           (default: $default_bucket)
   -N network              specified network type
                           (default: $default_network, valid values: ostn, stn, psn, lrtn, mainnet)
   -s snapshot             specify the snapshot to download
                           (default: $default_snapshot)


COMMANDS:
   setup                   install all the prerequisites
   download <shard #>      download/sync latest db snapshot (shard 0-3)
   upload <shard #>        upload/sync db snapshot (shard 0-3)
   list <shard #>          list all the db snapshot (shard 0-3)

EXAMPLES:

   $ME -v
   $ME -v -N ostn upload
   $ME -N ostn download
   $ME -s 20190327.123201 -t v0 download 0

EOF
   exit 0
}

unset -v VERBOSE NETWORK BUCKET NOW SNAPSHOT
unset -v option OPTARG OPTIND
OPTIND=1
NOW=$(date +%Y%m%d.%H%M%S)

while getopts "hvB:N:" option; do
   case $option in
      v) VERBOSE=true ;;
      B) BUCKET=${OPTARG} ;;
      N) NETWORK=${OPTARG} ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

: ${VERBOSE="${default_verbose}"}
: ${BUCKET="${default_bucket}"}
: ${NETWORK="${default_network}"}
: ${SNAPSHOT="${default_snapshot}"}
: ${TAG="${default_tag}"}

CMD=${1:-list}
shift

if ${VERBOSE}; then
   cat<<-EOT
   network: $NETWORK
   bucket: $BUCKET
   command: $CMD
EOT
fi

function do_setup
{
   logging 'install rclone'
   curl https://rclone.org/install.sh | sudo bash

   logging 'install jq'
   sudo apt-get install jq
}

function do_download_snapshot
{
   shards=$@
   _stop_harmony
   for s in $shards; do
      verbose download snapshot shard $s
      if [ "${SNAPSHOT}" == "latest" ]; then
      rclone sync -P hmy:${BUCKET}/snapshot/${NETWORK}/harmony_db_${s}/
      else
         rclone sync -P hmy:${BUCKET}/snapshot/${NETWORK}/harmony_db_${s}/${SNAPSHOT}.${TAG}/ harmony_db_${s}
      fi
   done
   _resume_harmony
}

function do_upload_snapshot
{
   shards=$@
   _stop_harmony
   for s in $shards; do
      verbose upload snapshot shard $s
      rclone sync -P harmony_db_${s} hmy:${BUCKET}/snapshot/harmony_db_${s}/${NETWORK}/${NOW}.${TAG}/
   done
   _resume_harmony
}

function list_snapshot
{
   shards=$1
   for s in $shards; do
      verbose list snapshot shard $s
      aws s3 ls s3://$BUCKET/snapshot/$NETWORK/harmony_db_${s}/
   done
}

###############################################################################
case $CMD in
   setup) do_setup ;;
   download) do_download_snapshot $@ ;;
   upload) do_upload_snapshot $@ ;;
   list) list_snapshot $@ ;;
   *) usage ;;
esac

# vim: expandtab:tabstop=3
