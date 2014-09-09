#!/bin/bash

#HOSTNAME=controller
DBPASS_ROOT=root_dbpass
DBPASS_KEYSTONE=keystone_dbpass
DBPASS_GLANCE=glance_dbpass
DBPASS_NOVA=nova_dbpass
DBPASS_CINDER=cinder_dbpass
DBPASS_DASH=dash_dbpass

# install required rpm
yum install -y python-pip python-virtualenv curl wget \
               git make gcc gcc-c++  m4 ncurses-devel \
               openssl-devel MySQL-python libcgroup \
               netcf-libs java-1.7.0-openjdk qemu-img \
               erlang rabbitmq-server-3.2.2 mysql \
               libguestfs python-libguestfs libguestfs-tools \
               mysql-server MySQL-python memcached mod_wsgi
#yum install -y libvirt libvirt-client libvirt-devel libvirt-python

# change hostname
#hostname $HOSTNAME
#sed -i "s/^HOSTNAME=.*\$/HOSTNAME=$HOSTNAME/g" /etc/sysconfig/network

# disable selinux
sed "s/^SELINUX=.*\$/SELINUX=disabled/g" /etc/selinux/config

# cleanup iptables
cp /etc/sysconfig/iptables /etc/sysconfig/iptables.bak
echo "">/etc/sysconfig/iptables
/etc/init.d/iptables restart

# start rabbit mq
chkconfig rabbitmq-server on
service rabbitmq-server restart

# start memcached
chkconfig memcached on
service memcached restart

# cp horizon conf
rm -rf  /etc/httpd/conf.d/horizon.conf
cp  /opt/op/horizon.conf /etc/httpd/conf.d/ 

# start httpd
chkconfig httpd on
service httpd restart

# create folder
# host data directory
rm -rf /openstack
rm -rf /datapool/*

mkdir -p /openstack/keystone/log \
        /openstack/keystone/run \
        /openstack/glance/log \
        /openstack/glance/run \
        /openstack/cinder/log \
        /openstack/cinder/run \
        /openstack/nova/log \
        /openstack/nova/run \
        /openstack/nova/networks 

# shared storage
mkdir -p /datapool/openstack/glance/images \
        /datapool/openstack/glance/image_cache \
        /datapool/openstack/cinder/pofs \
        /datapool/openstack/nova/instances 

#link shared storage
ln -s /datapool/openstack/glance/images /openstack/glance/
ln -s /datapool/openstack/glance/image_cache /openstack/glance/
ln -s /datapool/openstack/cinder/pofs /openstack/cinder/
ln -s /datapool/openstack/nova/instances /openstack/nova/

# edit & copy mysql conf
mv /etc/my.cnf /etc/my.cnf.bak
cp /opt/op/my.cnf /etc/

# start mysql
if [ ! -f /var/run/mysqld/mysqld.pid ]; then
    chkconfig mysqld on
    mysql_install_db && mysqld_safe &
    mysql_secure_installation 
fi


# add user
useradd -c 'OpenStack keystone Daemons' -s /sbin/nologin -d /home/keystone  keystone -M
useradd -c 'OpenStack glance Daemons' -s /sbin/nologin -d /home/glance glance -M
useradd -c 'OpenStack nova Daemons' -s /sbin/nologin -d /home/nova  nova  -M
useradd -c 'OpenStack cinder Daemons' -s /sbin/nologin -d /home/cinder cinder -M

# chown permission
chown -R apache:apache horizon
chown -R apache:apache horizon-new
chown -R keystone:keystone /openstack/keystone
chown -R glance:glance /openstack/glance
chown -R glance:glance /datapool/openstack/glance
chown -R nova:nova /openstack/nova
chown -R nova:nova /datapool/openstack/nova
chown -R cinder:cinder /openstack/cinder
chown -R cinder:cinder /datapool/openstack/cinder

# copy etc && init.d
rm -rf /etc/keystone
cp -rf /opt/etc/keystone /etc/

rm -rf /etc/nova
cp -rf /opt/etc/nova /etc/

rm -rf /etc/glance
cp -rf /opt/etc/glance /etc/

rm -rf /etc/cinder
cp -rf /opt/etc/cinder /etc/
    
cp -f /opt/etc/init.d/* /etc/init.d/

# add nova sudoer
if ! cat /etc/sudoers | grep nova ;then
    sed -i '/^root/a\nova    ALL=(root) NOPASSWD: /usr/bin/nova-rootwrap /etc/nova/rootwrap.conf *' /etc/sudoers
fi

# link binary 
ln -sf /opt/keystone/virtualenv/bin/keystone* /usr/bin/
ln -sf /opt/glance/virtualenv/bin/glance* /usr/bin/
ln -sf /opt/nova/virtualenv/bin/nova* /usr/bin/
ln -sf /opt/cinder/virtualenv/bin/cinder* /usr/bin/
ln -sf /opt/python-cinderclient/virtualenv/bin/cinder /usr/bin/
ln -sf /opt/python-novaclient/virtualenv/bin/nova  /usr/bin/
ln -sf /opt/python-glanceclient/virtualenv/bin/glance  /usr/bin/

# create database
mysql -uroot -p$DBPASS_ROOT -e 'CREATE DATABASE IF NOT EXISTS keystone;' 
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY \"$DBPASS_KEYSTONE\";"
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY \"$DBPASS_KEYSTONE\";"

mysql -uroot -p$DBPASS_ROOT -e 'CREATE DATABASE IF NOT EXISTS glance;' 
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY \"$DBPASS_GLANCE\";"
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY \"$DBPASS_GLANCE\";"

mysql -uroot -p$DBPASS_ROOT -e 'CREATE DATABASE IF NOT EXISTS nova;'
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY \"$DBPASS_NOVA\";"
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY \"$DBPASS_NOVA\";"

mysql -uroot -p$DBPASS_ROOT -e 'CREATE DATABASE IF NOT EXISTS dash;'
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON dash.* TO 'dash'@'localhost' IDENTIFIED BY \"$DBPASS_DASH\";"
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON dash.* TO 'dash'@'%' IDENTIFIED BY \"$DBPASS_DASH\";"

mysql -uroot -p$DBPASS_ROOT -e 'CREATE DATABASE IF NOT EXISTS cinder;'
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY \"$DBPASS_CINDER\";"
mysql -uroot -p$DBPASS_ROOT -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY \"$DBPASS_CINDER\";"

# remove this when all configs are modified
exit

su -s /bin/sh -c "keystone-manage db_sync" keystone
/etc/init.d/openstack-keystone-all start

sh keystone_data.sh

su -s /bin/sh -c "glance-manage db_sync" glance
/etc/init.d/openstack-glance-api start 
/etc/init.d/openstack-glance-registry start

su -s /bin/sh -c "nova-manage db sync" nova 
/etc/init.d/openstack-nova-api start
/etc/init.d/openstack-nova-scheduler start
/etc/init.d/openstack-nova-conductor start
/etc/init.d/openstack-nova-cert start
/etc/init.d/openstack-nova-consoleauth start
/etc/init.d/openstack-nova-novncproxy start

su -s /bin/sh -c "cinder-manage db sync" cinder
/etc/init.d/openstack-cinder-api start
/etc/init.d/openstack-cinder-scheduler start
