#!/bin/bash

set -e

TF=`mktemp`
pcs cluster cib $TF

RESULT=2

if ! pcs -f $TF resource show oVirtVM >/dev/null 2>&1; then
    pcs -f $TF resource create oVirtVM ocf:heartbeat:VirtualDomain config="/etc/oVirt.xml" hypervisor="qemu:///system" op start timeout="120" op stop timeout="120" op monitor timeout="30" interval="10"
    RESULT=0
fi

if ! pcs -f $TF constraint colocation show --full | grep -q 'oVirtVM with oVirtMasterVolume'; then
    pcs -f $TF constraint colocation add oVirtVM master oVirtMasterVolume
    RESULT=0
fi

if ! pcs -f $TF constraint order show --full | grep -q 'promote oVirtMasterVolume then start oVirtVM'; then
    pcs -f $TF constraint order promote oVirtMasterVolume then start oVirtVM
    RESULT=0
fi

for NODE in $*; do
    if ! pcs constraint location show resources oVirtVM | grep -q "Enabled on: $NODE "; then
	pcs -f $TF constraint location oVirtVM prefers "$NODE=100"
	RESULT=0
    fi
done

if [ $RESULT -eq 0 ]; then
    pcs cluster cib-push $TF
fi
rm -f $TF

exit $RESULT
