#!/bin/bash

set -e

TF=`mktemp`
pcs cluster cib $TF

RESULT=2

if ! pcs -f $TF resource show oVirtVolume >/dev/null 2>&1; then
    pcs -f $TF resource create oVirtVolume ocf:linbit:drbd drbd_resource=drbd0
    RESULT=0
fi

if ! pcs -f $TF resource show oVirtMasterVolume >/dev/null 2>&1; then
    pcs -f $TF resource master oVirtMasterVolume oVirtVolume master-max=1 master-node-max=1 clone-max=2 clone-node-max=2 notify=true
    RESULT=0
fi

for NODE in $*; do
    if ! pcs constraint location show resources oVirtMasterVolume | grep -q "Enabled on: $NODE "; then
	pcs -f $TF constraint location oVirtMasterVolume prefers "$NODE=100"
	RESULT=0
    fi
done

if [ $RESULT -eq 0 ]; then
    pcs cluster cib-push $TF
fi
rm -f $TF

RESTART_PACEMAKER=true
N=10
while [ $N -gt 0 ]; do
    if /usr/sbin/drbd-overview | grep -q -e Connected -e SyncTarget -e SyncSource; then
	RESTART_PACEMAKER=false
	break
    fi
    sleep 1
    N=$[$N-1]
done

if $RESTART_PACEMAKER; then
    systemctl restart pacemaker

    N=10
    while [ $N -gt 0 ]; do
	if /usr/sbin/drbd-overview | grep -q -e Connected -e SyncTarget -e SyncSource; then
	    break
	fi
	sleep 1
	N=$[$N-1]
    done

    exit 1
fi

if [ "`drbdadm role drbd0`" = "Secondary/Secondary" ]; then
    drbdadm primary --force drbd0
fi
while [ "`drbdadm role drbd0`" = "Secondary/Secondary" ]; do
    sleep 1
done
pcs resource cleanup oVirtVolume

exit $RESULT
