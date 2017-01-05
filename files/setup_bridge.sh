#!/bin/bash

BRIDGE="$1"
[ -z "$BRIDGE" ] && exit 1

DEV=`ip ro get 8.8.8.8 | awk '{for(I=1;I<NF;I++){if($I=="dev"){print$(I+1)}}}'`
[ "$DEV" = "$BRIDGE" ] && exit 2

[ -d "/sys/class/net/$DEV/bridge" ] && exit 1
[ -d "/sys/class/net/$DEV/brport" ] && exit 1
[ -f "/etc/sysconfig/network-scripts/ifcfg-$BRIDGE" ] && exit 1
[ -f "/etc/sysconfig/network-scripts/ifcfg-$DEV" ] || exit 1

cat >"/etc/sysconfig/network-scripts/ifcfg-$BRIDGE" <<EOF
DEVICE=$BRIDGE
TYPE=Bridge
DELAY=0
STP=off
ONBOOT=yes
NM_CONTROLLED=no
HOTPLUG=no
EOF

grep -e ^IPADDR -e ^NETMASK -e ^GATEWAY -e ^BOOTPROTO "/etc/sysconfig/network-scripts/ifcfg-$DEV" >>"/etc/sysconfig/network-scripts/ifcfg-$BRIDGE"
sed -i '/^IPADDR/d;/^NETMASK/d;/^GATEWAY/d;/^BOOTPROTO/d' "/etc/sysconfig/network-scripts/ifcfg-$DEV"
echo "BRIDGE=$BRIDGE" >>"/etc/sysconfig/network-scripts/ifcfg-$DEV"

systemctl restart network || exit 1

exit 0
