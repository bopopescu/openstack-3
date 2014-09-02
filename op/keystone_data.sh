#!/bin/bash
#
# Initial data for Keystone using python-keystoneclient
# Defaults

source /opt/keystone/virtualenv/bin/activate

# if ADMIN_PASSWORD is null or not set, "admin_pass" is used
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin_pass}
GLANCE_PASSWORD=${GLANCE_PASSWORD:-glance_pass}
NOVA_PASSWORD=${NOVA_PASSWORD:-nova_pass}
CINDER_PASSWORD=${CINDER_PASSWORD:-cinder_pass}

KEYSTONE_IP=192.168.18.6
export SERVICE_TOKEN=484595584febaddcf2b3
export SERVICE_ENDPOINT=http://$KEYSTONE_IP:35357/v2.0

function get_id () {
echo `"$@" | awk '/ id / { print $4 }'`
}

# Tenants

ADMIN_TENANT=$(get_id keystone tenant-create \
--name=admin)

SERVICE_TENANT=$(get_id keystone tenant-create \
--name=service)

#
# Users
ADMIN_USER=$(get_id keystone user-create \
--name=admin \
--pass="$ADMIN_PASSWORD" \
--tenant-id $ADMIN_TENANT )

GLANCE_USER=$(get_id keystone user-create \
--name=glance \
--pass="$GLANCE_PASSWORD" \
--tenant-id $SERVICE_TENANT )

NOVA_USER=$(get_id keystone user-create \
--name=nova \
--pass="$NOVA_PASSWORD" \
--tenant-id $SERVICE_TENANT )

CINDER_USER=$(get_id keystone user-create \
--name=cinder \
--pass="$CINDER_PASSWORD" \
--tenant-id $SERVICE_TENANT )

# Roles
ADMIN_ROLE=$(get_id keystone role-create \
--name=admin)
# The Member role is used by Horizon and Swift so we need to keep it:
MEMBER_ROLE=$(get_id keystone role-create \
--name=Member)

# Add Roles to Users in Tenants
keystone user-role-add \
--user_id $ADMIN_USER \
--role_id $ADMIN_ROLE \
--tenant_id $ADMIN_TENANT

keystone user-role-add \
--user_id $GLANCE_USER \
--role_id $ADMIN_ROLE \
--tenant_id $SERVICE_TENANT

keystone user-role-add \
--user_id $NOVA_USER \
--role_id $ADMIN_ROLE \
--tenant_id $SERVICE_TENANT

keystone user-role-add \
--user_id $CINDER_USER \
--role_id $ADMIN_ROLE \
--tenant_id $SERVICE_TENANT

# Services

#creat service catalog and service endpoints
KEYSTONE_SERVICE_ID=$(get_id keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT \
service-create \
--name=keystone \
--type=identity \
--description="Keystone Identity Service")

keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT/ \
endpoint-create \
--region RegionOne \
--service-id=$KEYSTONE_SERVICE_ID \
--publicurl=http://$KEYSTONE_IP:5000/v2.0 \
--internalurl=http://$KEYSTONE_IP:5000/v2.0 \
--adminurl=http://$KEYSTONE_IP:35357/v2.0
NOVA_SERVICE_ID=$(get_id keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT \
service-create \
--name=nova \
--type=compute \
--description="Nova Compute Service")

keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT/ \
endpoint-create \
--region RegionOne \
--service-id=$NOVA_SERVICE_ID \
--publicurl="http://$KEYSTONE_IP:8774/v2/%(tenant_id)s" \
--internalurl="http://$KEYSTONE_IP:8774/v2/%(tenant_id)s" \
--adminurl="http://$KEYSTONE_IP:8774/v2/%(tenant_id)s"

IMAGE_SERVICE_ID=$(get_id keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT \
service-create \
--name=glance \
--type=image \
--description="OpenStack Glance Image Service")

keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT/ \
endpoint-create \
--region RegionOne \
--service-id=$IMAGE_SERVICE_ID \
--publicurl=http://$KEYSTONE_IP:9292/v2.0 \
--internalurl=http://$KEYSTONE_IP:9292/v2.0 \
--adminurl=http://$KEYSTONE_IP:9292/v2.0

VOLUMES_SERVICE_ID=$(get_id keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT \
service-create \
--name=cinder \
--type=volume \
--description="OpenStack Block Storage v1")

keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT/ \
endpoint-create \
--region RegionOne \
--service-id=$VOLUMES_SERVICE_ID \
--publicurl="http://$KEYSTONE_IP:8776/v1/%(tenant_id)s" \
--internalurl="http://$KEYSTONE_IP:8776/v1/%(tenant_id)s" \
--adminurl="http://$KEYSTONE_IP:8776/v1/%(tenant_id)s"

VOLUMES2_SERVICE_ID=$(get_id keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT \
service-create \
--name=cinderv2 \
--type=volumev2 \
--description="OpenStack Block Storage v2")

keystone --os-token $SERVICE_TOKEN \
--os-endpoint $SERVICE_ENDPOINT/ \
endpoint-create \
--region RegionOne \
--service-id=$VOLUMES22_SERVICE_ID \
--publicurl="http://$KEYSTONE_IP:8776/v2/%(tenant_id)s" \
--internalurl="http://$KEYSTONE_IP:8776/v2/%(tenant_id)s" \
--adminurl="http://$KEYSTONE_IP:8776/v2/%(tenant_id)s"
