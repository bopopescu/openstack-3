#!/bin/bash

#HOSTNAME=controller

# install required rpm
yum install -y python-pip python-virtualenv curl wget \
               git make gcc gcc-c++  m4 ncurses-devel \
               openssl-devel MySQL-python libcgroup \
               netcf-libs java-1.7.0-openjdk qemu-img \
               erlang rabbitmq-server-3.2.2 mysql \
               libguestfs python-libguestfs libguestfs-tools \
               mysql-server MySQL-python libvirt libvirt-client \
               libvirt-devel libvirt-python

# change hostname
#hostname $HOSTNAME
#sed -i "s/^HOSTNAME=.*\$/HOSTNAME=$HOSTNAME/g" /etc/sysconfig/network

# disable selinux
sed "s/^SELINUX=.*\$/SELINUX=disabled/g" /etc/selinux/config

# cleanup iptables
cp /etc/sysconfig/iptables /etc/sysconfig/iptables.bak
echo "">/etc/sysconfig/iptables
/etc/init.d/iptables restart

# create folder
if [ ! -d /openstack/keystone ]; then
    # host data directory
    mkdir -p /openstack/nova/log \
             /openstack/nova/run \
             /openstack/nova/networks 

    #link shared storage
    ln -s /datapool/openstack/nova/instances /openstack/nova/
fi

# add user
if ! id nova ; then
    useradd -c 'OpenStack nova Daemons' -s /sbin/nologin -d /home/nova  nova  -M
fi

# chown permission
chown -R nova:nova /openstack/nova
chown -R nova:nova /datapool/openstack/nova

# copy etc && init.d
rm -rf /etc/nova    
cp -rf /opt/etc/nova /etc/

rm -f /etc/init.d/openstack-nova-api-metadata 
cp -f /opt/etc/init.d/openstack-nova-api-metadata  /etc/init.d/

rm -f /etc/init.d/openstack-nova-compute 
cp -f /opt/etc/init.d/openstack-nova-compute  /etc/init.d/

rm -f /etc/init.d/openstack-nova-network
cp -f /opt/etc/init.d/openstack-nova-network  /etc/init.d/

# add nova sudoer
if ! cat /etc/sudoers | grep nova ;then
    sed -i '/^root/a\nova    ALL=(root) NOPASSWD: /usr/bin/nova-rootwrap /etc/nova/rootwrap.conf *' /etc/sudoers
fi

# link binary 
if [ ! -f /usr/bin/nova ]; then
    ln -sf /opt/nova/virtualenv/bin/nova* /usr/bin/
    ln -sf /opt/python-novaclient/virtualenv/bin/nova  /usr/bin/
fi

cp -f /opt/op/50-nova.pkla  /etc/polkit-1/localauthority/50-local.d/
