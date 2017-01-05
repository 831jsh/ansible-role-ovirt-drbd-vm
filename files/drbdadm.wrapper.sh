#!/bin/bash

[ "$1" = "syncer" ] && exit 0

exec /usr/sbin/drbdadm $*
