�����������root�û����У�

ʾ�����û�����
���ƽڵ�1̨��ip 192.168.18.6
����ڵ�1̨��ip 192.168.18.235

�������192.168.18.6:/mnt/op-install.tgz 

������ƽڵ㣺
��1����ѹop-deploy��/opt Ŀ¼��tar zxf /mnt/op-install.tgz -C /opt/

��2�����ع���洢��/datapoolĿ¼����glusterΪ������
        mkdir -p /datapool
        mount -t glusterfs 10.64.0.32:/sharevol /datapool

��3���޸�/etc/sudoers
        ע�͸��У�
        Defaults requiretty

��4��ִ�п��ƽڵ��ʼ���ű���
        cd /opt/op
        sh control_init.sh
        ִ����������ʾ��Change the root password? [Y/n]������Y������"root_dbpass"��������ֱ�ӻس�����

��5���޸�keystone�����ļ���/etc/keystone/keystone.conf����
        �޸�ip��ַΪ�ڵ�ip��
	public_endpoint=http://192.168.18.6:5000/v2.0/ 
	admin_endpoint=http://192.168.18.6:35357/v2.0/

��6����ʼ��keystone���ݿ⣺
         su -s /bin/sh -c "keystone-manage db_sync" keystone

��7������keystone��
        /etc/init.d/openstack-keystone-all start 

��8���޸�/opt/op/keystone_data.sh
	�޸�keystone ������ַ��
	KEYSTONE_IP=192.168.18.6

��9��ִ��keystone_data.sh:
         cd /opt/op; sh keystone_data.sh

��10����ʼ��glance���ݿ⣺
        su -s /bin/sh -c "glance-manage db_sync" glance

��11������glance����
        /etc/init.d/openstack-glance-api start
        /etc/init.d/openstack-glance-registry start

        *�����ϴ�����* 
        source /opt/op/admin-openrc.sh 
        glance image-create --name CentOS-6.4-x86_64 --disk-format=qcow2 --container-format=ovf < /mnt/CentOS-6.4-x86_64.img 
 	*���Ծ����ļ���CentOS-6.4-x86_64.img��192.168.18.6��/mntĿ¼��*

��12���޸�nova���ã�/etc/nova/nova.conf����
        �޸�����ip��
        my_ip=192.168.18.6
        
        �޸�vnc proxy��ַ��
        vncserver_proxyclient_address=192.168.18.6
        novncproxy_base_url = http://192.168.18.6:6080/vnc_auto.html

        �޸��������ã����������������network�����ڴ������ڣ�
        fixed_range=192.168.18.80/28
        
��13����ʼ��nova���ݿ�:
        su -s /bin/sh -c "nova-manage db sync" nova

��14������nova����
	/etc/init.d/openstack-nova-api start
	/etc/init.d/openstack-nova-scheduler start
	/etc/init.d/openstack-nova-conductor start
	/etc/init.d/openstack-nova-cert start
	/etc/init.d/openstack-nova-consoleauth start
	/etc/init.d/openstack-nova-novncproxy start

��15���޸�cinder�����ļ���/etc/cinder/cinder.conf����
	�޸ı���ip��
	my_ip=192.168.18.6

��16����ʼ��cinder ���ݿ⣺
	su -s /bin/sh -c "cinder-manage db sync" cinder

��17������cinder
        /etc/init.d/openstack-cinder-api start
        /etc/init.d/openstack-cinder-scheduler start
        /etc/init.d/openstack-cinder-volume start

��18��������ڵ㲿����ɺ󣬴������磺
        nova network-create --fixed-range-v4 192.168.18.80/28 --multi-host T --gateway 192.168.18.1 net1

����̨��ַ��http://192.168.18.6/

�������ڵ㣺
��1����ѹop-deploy��/opt Ŀ¼��tar zxf /mnt/op-install.tgz -C /opt/

��2�����ع���洢��/datapoolĿ¼����glusterΪ������
         mkdir -p /datapool
         mount -t glusterfs 10.64.0.32:/sharevol /datapool

��3������br0���ţ�
         ����Ϊʾ����������������ݸ��������������ָ����
        echo 1 > /proc/sys/net/ipv4/ip_forward
        ifconfig eth11 0.0.0.0
        brctl addbr br0
        brctl addif br0 eth11
        ifconfig br0 192.168.18.235 broadcast 192.168.18.255 up

��4������libvirtd��
        �޸�/etc/libvirt/libvirtd.conf
        listen_tls = 0
        listen_tcp = 1
        auth_tcp = "none"
        /etc/init.d/libvirtd restart
        
��5���޸�/etc/sudoers
        ע�͸��У�
        Defaults requiretty
        ��ɣ�
        # Defaults requiretty 

��6��ִ�м���ڵ��ʼ���ű���
        cd /opt/op
        sh compute_init.sh

��7���޸�nova ���ã�
        *�޸�/etc/nova/nova.conf*
        �޸�����ip
        my_ip=192.168.18.235

        ���mq��ַΪ���ƽڵ�ip��
        rabbit_host=192.168.18.6

        �޸���֤�����ַΪ���ƽڵ�ip��
        identity_uri = http://192.168.18.6:35357 
        auth_uri=http://192.168.18.6:5000

        auth_host=192.168.18.6
        
        �޸����ݿ��ַΪ���ƽڵ�ip��
        connection=mysql://nova:nova_dbpass@192.168.18.6/nova

        �޸�glance api��ַΪ���ƽڵ�ip��
        api_servers=192.168.18.6:9292

        *�޸�/etc/nova/nova-dhcpbridge.conf*
        �޸����ݿ��ַΪ���ƽڵ�ip��
        connection=mysql://nova:nova_dbpass@192.168.18.6/nova

��8������nova��
        /etc/init.d/openstack-nova-compute start
        /etc/init.d/openstack-nova-network start
