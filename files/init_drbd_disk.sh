#!/bin/bash

DRBD="$1"
DEVICE="$2"

[ -b "$DEVICE" ] || exit 1

# check if device is already initialized
TYPE=`blkid -s TYPE -o value "$DEVICE"`
[ "$TYPE" = "drbd" ] && exit 2

# check if device is mounted
MOUNTPOINT=`lsblk -o MOUNTPOINT -n "$DEVICE"`
[ -z "$MOUNTPOINT" ] || exit 1

dd if=/dev/zero of="$DEVICE" bs=1M count=64 2>/dev/null || exit 1
drbdadm create-md "$DRBD" || exit 1

exit 0
