#!/bin/bash

set -e

[ -b /dev/drbd0 ] || exit 1

ROLE=`drbdadm role drbd0`
[ "$ROLE" = "Secondary/Primary" ] && exit 2
[ "$ROLE" = "Primary/Secondary" ] || exit 1

SWAPSIZE=""
HNAME=""
IPADDR=""
NETMASK=""
GATEWAY=""
RESOLV=""
PASS=""

while getopts "t:d:s:n:i:m:g:r:p:" opt; do
    case $opt in
	s)
	    SWAPSIZE="$OPTARG"
	    ;;
	n)
	    HNAME="$OPTARG"
	    ;;
	i)
	    IPADDR="$OPTARG"
	    ;;
	m)
	    NETMASK="$OPTARG"
	    ;;
	g)
	    GATEWAY="$OPTARG"
	    ;;
	r)
	    RESOLV="$OPTARG"
	    ;;
	p)
	    PASS="$OPTARG"
	    ;;
    esac
done

ROOT=/mnt/create_ovirt_disk

function umount_root {
    # umount if it is
    awk -vM=$ROOT 'substr($2,0,length(M))==M{print$2}' /proc/mounts | tac | xargs -l1 --no-run-if-empty umount
    if [ -d $ROOT ]; then
	rmdir $ROOT
    fi
    # remove partitions
    kpartx -d /dev/drbd0
}
umount_root

# check if already formated
PTTYPE=`/usr/sbin/blkid -s PTTYPE -o value /dev/drbd0 || :`
[ -n "$PTTYPE" ] && exit 2

# make partitions
yes | parted /dev/drbd0 "mklabel msdos" || :
if [ -z "$SWAPSIZE" ]; then
    yes | parted /dev/drbd0 "mkpart primary ext4 1M -1"
else
    yes | parted /dev/drbd0 "mkpart primary linux-swap 1M ${SWAPSIZE}M" || :
    yes | parted /dev/drbd0 "mkpart primary ext4 ${SWAPSIZE}M -1" || :
fi

kpartx -a /dev/drbd0
sleep 1

# format
mkswap /dev/mapper/drbd0p1
mkfs.ext4 /dev/mapper/drbd0p2

SWAPID=`blkid -s UUID -o value /dev/mapper/drbd0p1`
ROOTID=`blkid -s UUID -o value /dev/mapper/drbd0p2`

# mount
mkdir -p $ROOT
mount /dev/mapper/drbd0p2 $ROOT
mkdir -p $ROOT/dev
mount --bind /dev $ROOT/dev
mkdir -p $ROOT/proc
mount --bind /proc $ROOT/proc
mkdir -p $ROOT/sys
mount --bind /sys $ROOT/sys
mkdir -p $ROOT/run
mount --bind /run $ROOT/run

# /etc/fstab
mkdir -p $ROOT/etc
cat >$ROOT/etc/fstab <<EOF
UUID=$ROOTID / ext4 defaults 0 0
tmpfs /dev/shm tmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620  0 0
sysfs /sys sysfs defaults 0 0
proc /proc proc defaults 0 0
UUID=$SWAPID swap swap defaults 0 0
EOF

# /etc/mtab
touch $ROOT/etc/mtab

# create /tmp/yum.conf
mkdir $ROOT/tmp
cat >$ROOT/tmp/yum.conf <<EOF
[main]
cachedir=/var/cache/yum
keepcache=1
debuglevel=2
logfile=/var/log/yum.log
distroverpkg=redhat-release
tolerant=1
exactarch=1
gpgcheck=1
plugins=0
assumeyes=1

[base]
name=Base
baseurl=http://mirror.centos.org/centos/7/os/x86_64/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=Updates
baseurl=http://mirror.centos.org/centos/7/updates/x86_64/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

RPMS="
acl
anacron
basesystem
bc
bind-utils
bridge-utils
btrfs-progs
compat-libstdc++-33
curl
device-mapper
dhclient
dmidecode
dosfstools
e2fsprogs
ed
efibootmgr
eject
file
finger
freeipmi
ftp
genisoimage
grub2
hdparm
initscripts
ipmitool
iptables
iptables-services
iptstate
irqbalance
iscsi-initiator-utils
kbd
kernel
kernel-tools
kexec-tools
keyutils
lftp
libxslt
linux-firmware
logwatch
lsof
lvm2
lynx
mailcap
make
man
man-db
man-pages
mc
mdadm
microcode_ctl
mkisofs
nc
net-snmp
net-snmp-perl
net-tools
newt
nfs-utils
nmap-ncat
ntp
OpenIPMI-tools
openssh-clients
openssh-server
openssl
parted
passwd
patch
pciutils
perl-macros
perl(Time::HiRes)
plymouth-scripts
policycoreutils
quota
rootfiles
rpm
rpm-build
rsh
rsync
rsyslog
screen
sendmail
setserial
strace
sudo
sysfsutils
systemd-sysv
tcpdump
teamd
telnet
time
tmpwatch
traceroute
unzip
usbutils
usermode
util-linux
vim-enhanced
vim-minimal
wget
which
whois
xfsprogs
yum
yum-utils
zip
"

# yum install
mkdir -p $ROOT/etc/yum.repos.d
yum -c "$ROOT/tmp/yum.conf" --installroot="$ROOT" -y -q install $RPMS

# cleanup
rm -rf $ROOT/var/cache/yum/*
rm -rf $ROOT/var/lib/yum/*/*

echo Rebuilding RPM database
rm -f $ROOT/var/lib/rpm/__db.*
chroot $ROOT rpm --rebuilddb
rm -f $ROOT/var/lib/rpm/__db.*

# i18n
cat >$ROOT/etc/sysconfig/i18n <<EOF
LANG=C
SYSFONT=latarcyrheb-sun16
EOF

# enable networking
cat >$ROOT/etc/sysconfig/network <<EOF
NETWORKING=yes
NOZEROCONF=yes
IPV6FORWARDING=no
EOF

# blacklist DRM modules
for f in $ROOT/lib/modules/*/kernel/drivers/gpu/drm $ROOT/lib/modules/*/kernel/drivers/char/drm; do
    [ -d "$f" ] || continue
    find $f -type f | sed 's|\.ko$||;s|^.*/|blacklist |' >>$ROOT/etc/modprobe.d/blacklist-drm.conf
done

# auto install new kernels
cat >$ROOT/etc/sysconfig/kernel <<EOF
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel

# MAKEDEBUG specifies if new-kernel-pkg should create non-default
# "debug" entries for new kernels.
MAKEDEBUG=false
EOF

# importing rpm keys
for f in `grep ^gpgkey= $ROOT/etc/yum.repos.d/*.repo | awk -F= '{print $2}' | sort -u`; do
    echo "Importing $ROOT/${f##file:///}"
    rpm --root $ROOT --import "$ROOT/${f##file:///}"
done

# re-create initramfs
echo Creating ramdisk
KVER=`rpm --root $ROOT -q kernel --qf '%{version}-%{release}.%{arch}'`
chroot $ROOT /usr/sbin/dracut --force --kver "$KVER" --add-drivers "virtio virtio_net virtio_blk virtio_scsi virtio_pci"

# install grub
cat >$ROOT/etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT=serial
GRUB_CMDLINE_LINUX="rhgb quiet selinux=0 console=ttyS0"
GRUB_SERIAL_COMMAND="serial"
GRUB_DISABLE_RECOVERY=true
EOF
chroot $ROOT /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot $ROOT /usr/sbin/grub2-install /dev/drbd0

if [ -n "$HNAME" ]; then
    echo "$HNAME" >$ROOT/etc/hostname
fi

if [ -n "$IPADDR" -a -n "$NETMASK" -a -n "$GATEWAY" ]; then
cat >$ROOT/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE=eth0
ONBOOT=yes
IPADDR=$IPADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
EOF
fi
if [ "$IPADDR" = "dhcp" ]; then
cat >$ROOT/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
EOF
fi

# set root password
if [ -z "$PASS" ]; then
    # empty password
    PASS='$1$8BoJwJXM$wo/KQ1xFevweEjvXFa.VZ0'
fi
echo "root:$PASS" | chroot $ROOT /usr/sbin/chpasswd -e

if [ -n "$RESOLV" ]; then
    echo "$RESOLV" | awk -F, '{for(I=1;I<=NF;I++){print "nameserver "$I}}' >$ROOT/etc/resolv.conf
fi

if [ -f /root/.ssh/authorized_keys ]; then
    mkdir -m700 $ROOT/root/.ssh
    cp -f /root/.ssh/authorized_keys $ROOT/root/.ssh/authorized_keys
fi

umount_root

exit 0
