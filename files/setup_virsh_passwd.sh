#!/bin/bash

umask 027

if [ ! -f /etc/libvirt/auth.conf ]; then
    touch /etc/libvirt/auth.conf
fi

RESULT=0

if ! grep -q '^\[credentials-root\]' /etc/libvirt/auth.conf; then
    PASSWD=`dd if=/dev/urandom bs=1M count=1 2>/dev/null | md5sum | awk '{print $1}'`
    echo $PASSWD | saslpasswd2 -f /etc/libvirt/passwd.db -c -p root 2>/dev/null || exit 1
    cat >>/etc/libvirt/auth.conf <<EOF
[credentials-root]
authname=root
password=$PASSWD

EOF
    RESULT=2
fi

if ! grep -q '^\[auth-libvirt-localhost\]' /etc/libvirt/auth.conf; then
    cat >>/etc/libvirt/auth.conf <<EOF
[auth-libvirt-localhost]
credentials=root

EOF
    RESULT=2
fi

exit $RESULT
