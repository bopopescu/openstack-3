以下命令均以root用户运行：

示例配置环境：
控制节点1台：ip 192.168.18.6
计算节点1台：ip 192.168.18.235

部署包：192.168.18.6:/mnt/op-install.tgz 

部署控制节点：
（1）解压op-deploy至/opt 目录：tar zxf /mnt/op-install.tgz -C /opt/

（2）挂载共享存储至/datapool目录（以gluster为例）：
        mkdir -p /datapool
        mount -t glusterfs 10.64.0.32:/sharevol /datapool

（3）修改/etc/sudoers
        注释该行：
        Defaults requiretty

（4）执行控制节点初始化脚本：
        cd /opt/op
        sh control_init.sh
        执行中遇到提示：Change the root password? [Y/n]，输入Y，键入"root_dbpass"，其他的直接回车即可

（5）修改keystone配置文件（/etc/keystone/keystone.conf）：
        修改ip地址为节点ip：
	public_endpoint=http://192.168.18.6:5000/v2.0/ 
	admin_endpoint=http://192.168.18.6:35357/v2.0/

（6）初始化keystone数据库：
         su -s /bin/sh -c "keystone-manage db_sync" keystone

（7）启动keystone：
        /etc/init.d/openstack-keystone-all start 

（8）修改/opt/op/keystone_data.sh
	修改keystone 主机地址：
	KEYSTONE_IP=192.168.18.6

（9）执行keystone_data.sh:
         cd /opt/op; sh keystone_data.sh

（10）初始化glance数据库：
        su -s /bin/sh -c "glance-manage db_sync" glance

（11）启动glance服务：
        /etc/init.d/openstack-glance-api start
        /etc/init.d/openstack-glance-registry start

        *测试上传镜像* 
        source /opt/op/admin-openrc.sh 
        glance image-create --name CentOS-6.4-x86_64 --disk-format=qcow2 --container-format=ovf < /mnt/CentOS-6.4-x86_64.img 
 	*测试镜像文件：CentOS-6.4-x86_64.img，192.168.18.6：/mnt目录下*

（12）修改nova配置（/etc/nova/nova.conf）：
        修改主机ip：
        my_ip=192.168.18.6
        
        修改vnc proxy地址：
        vncserver_proxyclient_address=192.168.18.6
        novncproxy_base_url = http://192.168.18.6:6080/vnc_auto.html

        修改子网配置（后续创建的虚拟机network必须在此子网内）
        fixed_range=192.168.18.80/28
        
（13）初始化nova数据库:
        su -s /bin/sh -c "nova-manage db sync" nova

（14）启动nova服务：
	/etc/init.d/openstack-nova-api start
	/etc/init.d/openstack-nova-scheduler start
	/etc/init.d/openstack-nova-conductor start
	/etc/init.d/openstack-nova-cert start
	/etc/init.d/openstack-nova-consoleauth start
	/etc/init.d/openstack-nova-novncproxy start

（15）修改cinder配置文件（/etc/cinder/cinder.conf）：
	修改本机ip：
	my_ip=192.168.18.6

（16）初始化cinder 数据库：
	su -s /bin/sh -c "cinder-manage db sync" cinder

（17）启动cinder
        /etc/init.d/openstack-cinder-api start
        /etc/init.d/openstack-cinder-scheduler start
        /etc/init.d/openstack-cinder-volume start

（18）待计算节点部署完成后，创建网络：
        nova network-create --fixed-range-v4 192.168.18.80/28 --multi-host T --gateway 192.168.18.1 net1

控制台地址：http://192.168.18.6/

部署计算节点：
（1）解压op-deploy至/opt 目录：tar zxf /mnt/op-install.tgz -C /opt/

（2）挂载共享存储至/datapool目录（以gluster为例）：
         mkdir -p /datapool
         mount -t glusterfs 10.64.0.32:/sharevol /datapool

（3）创建br0网桥：
         以下为示例操作，参数请根据各服务器网络情况指定：
        echo 1 > /proc/sys/net/ipv4/ip_forward
        ifconfig eth11 0.0.0.0
        brctl addbr br0
        brctl addif br0 eth11
        ifconfig br0 192.168.18.235 broadcast 192.168.18.255 up

（4）配置libvirtd：
        修改/etc/libvirt/libvirtd.conf
        listen_tls = 0
        listen_tcp = 1
        auth_tcp = "none"
        /etc/init.d/libvirtd restart
        
（5）修改/etc/sudoers
        注释该行：
        Defaults requiretty
        变成：
        # Defaults requiretty 

（6）执行计算节点初始化脚本；
        cd /opt/op
        sh compute_init.sh

（7）修改nova 配置：
        *修改/etc/nova/nova.conf*
        修改主机ip
        my_ip=192.168.18.235

        需改mq地址为控制节点ip：
        rabbit_host=192.168.18.6

        修改验证服务地址为控制节点ip：
        identity_uri = http://192.168.18.6:35357 
        auth_uri=http://192.168.18.6:5000

        auth_host=192.168.18.6
        
        修改数据库地址为控制节点ip：
        connection=mysql://nova:nova_dbpass@192.168.18.6/nova

        修改glance api地址为控制节点ip：
        api_servers=192.168.18.6:9292

        *修改/etc/nova/nova-dhcpbridge.conf*
        修改数据库地址为控制节点ip：
        connection=mysql://nova:nova_dbpass@192.168.18.6/nova

（8）启动nova：
        /etc/init.d/openstack-nova-compute start
        /etc/init.d/openstack-nova-network start
