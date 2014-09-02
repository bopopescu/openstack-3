# vim: tabstop=4 shiftwidth=4 softtabstop=4

# Copyright (c) 2012 NetApp, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import errno
import hashlib
import os
import uuid
import statvfs
import shutil

from oslo.config import cfg


from cinder.openstack.common import fileutils,processutils
#from cinder import flags
from cinder import exception
from cinder.openstack.common import log as logging
from cinder.volume import driver

LOG = logging.getLogger(__name__)

volume_opts = [
    cfg.BoolOpt('using_sparsed_format',
                default=True,
                help=('Create volumes as sparsed files which take no space.'
                      'If set to False volume is created as regular file.'
                      'In such case volume creation takes a lot of time.')),
    cfg.StrOpt('pofs_mount_point', 
                default='/data/openstack/cinder/pofs',
                help=('The mount point of POFS storage')),
    cfg.StrOpt('ebs_volume_directory',
                default='volume_ebs', 
                help=('EBS volume storage directroy name, under pofs_mount_point')),
    cfg.StrOpt('ebs_snapshot_directory',
                default='volume_snapshot',    
                help=('EBS volume snapshot storage directroy name, under pofs_mount_point')),
    cfg.IntOpt('number_of_copies',
                default=3,
                help=('The count of copies for EBS image file store ')),  
    cfg.IntOpt('ebs_reserved_percentage',
                default=10,
                help=('Reserved percentage for pofs storage space, to prevent storage resource depletion')), 
    cfg.BoolOpt('simulate_pofs_ebs', 
               default=True,
               help=('Using Local storage for test EBS if True, '
                     'using pofs_storage for online machine with False')),    
    cfg.StrOpt('high_speed_mount_point', 
               default='/data/high_speed_volume', 
               help=('High speed volume mount point for EBS Storage')),
]

CONF = cfg.CONF
CONF.register_opts(volume_opts)
CONF.import_opt('volume_name_template', 'cinder.db')

class BaseFsDriver(driver.VolumeDriver):
    """Common base for drivers that work like NFS."""

    def check_for_setup_error(self):
        """Just to override parent behavior."""
        pass

    def create_volume(self, volume):
        raise NotImplementedError()

    def delete_volume(self, volume):
        raise NotImplementedError()

    def delete_snapshot(self, snapshot):
        """Do nothing for this driver, but allow manager to handle deletion
           of snapshot in error state."""
        pass

    def ensure_export(self, ctx, volume):
        raise NotImplementedError()

    def _create_sparsed_file(self, path, size):
        """Creates file with 0 disk usage."""
        if os.path.exists(path):
            msg = (_("Volume %s already exists."%volume['name']))
            LOG.info(msg)
            return
        else:
             self._execute('qemu-img', 'create', '-f', 'qcow2', \
                           '%s'%path, '%sG'%size, run_as_root=True)

    def _create_regular_file(self, path, size):
        """Creates regular file of given size. Takes a lot of time for large
        files."""
        KB = 1024
        MB = KB * 1024
        GB = MB * 1024

        block_size_mb = 1
        block_count = size * GB / (block_size_mb * MB)
        if os.path.exists(path):
            msg = (_("Volume %s already exists."%volume['name']))
            LOG.info(msg)
            return
        else:
            self._execute('dd', 'if=/dev/zero', 'of=%s' % path,
                      'bs=%dM' % block_size_mb,
                      'count=%d' % block_count,
                      run_as_root=True)

    def _set_rw_permissions_for_all(self, path):
        """Sets 666 permissions for the path."""
        self._execute('chmod', 'ugo+rw', path, run_as_root=True)

    def local_path(self, volume):
        """Get volume path (mounted locally fs path) for given volume
        :param volume: volume reference
        """
        return os.path.join(volume['provider_location'], volume['name'])

    def _path_exists(self, path):
        """Check for existence of given path."""
        try:
            self._execute('stat', path, run_as_root=True)
            return True
        except exception.ProcessExecutionError as exc:
            if 'No such file or directory' in exc.stderr:
                return False
            else:
                msg = (_("Failed stat %s ."%(path)))
                LOG.error(msg)
                return False

    def _get_hash_str(self, base_str):
        """returns string that represents hash of base_str
        (in a hex format)."""
        return hashlib.md5(base_str).hexdigest()


class FileDriver(BaseFsDriver):
    """File based cinder driver. Creates file on postorage for using it
    as block device on hypervisor."""
    def __init__(self, *args, **kwargs):
        super(FileDriver, self).__init__(*args, **kwargs)
        self.configuration.append_config_values(volume_opts)

    def do_setup(self, context):
        """Any initialization the volume driver does while starting"""
        super(FileDriver, self).do_setup(context)
        
        self._ensure_ebs_exist()
        self._test_ebs_rw()

    def create_cloned_volume(self, volume, src_vref):
        raise NotImplementedError()

    def create_volume(self, volume):
        """Creates a volume"""

        #self._ensure_ebs_exist()
        self._test_ebs_rw()

        volume['provider_location'] = self._get_volume_location(volume['id'])
        LOG.info(_('Volume location %s') % volume['provider_location'])

        self._do_create_volume(volume)

        return {'provider_location': volume['provider_location']}

    def create_volume_from_snapshot(self, volume, snapshot):
        """Creates a volume from a snapshot."""
        LOG.info('Create volume %s from snapshot %s'%(volume['id'], snapshot['id']))

        self.create_volume(volume)
        volume_size_mb = volume['size'] * 1024
        volume_path = self._get_volume_path(volume['id'])
        snapshot_path = self._get_snapshot_path(snapshot['id'])
       
        LOG.info('Copying snapshot %s data to volume %s .'%(snapshot['id'], volume['id'])) 
        cmd = ('dd', 'if=%s'%snapshot_path, 'of=%s'%volume_path, 'bs=1M', 'count=%s'%volume_size_mb)
        processutils.execute(*cmd, run_as_root=True) 
        LOG.info('Finished data Copy from snapshot %s to volume %s .'%(snapshot['id'], volume['id']))
       
    def delete_volume(self, volume):
        """Deletes a logical volume."""

        if not volume['provider_location']:
            LOG.warn(_('Volume %s does not have provider_location specified, '
                     'skipping'), volume['name'])
            return

        mounted_path = self.local_path(volume)

        #if not self._path_exists(mounted_path):
        if not os.path.exists(mounted_path):
            volume = volume['name']

            LOG.warn(_('Trying to delete non-existing volume %(volume)s at '
                     'path %(mounted_path)s') % locals())
            return

        recycle = self.recycle_path()
        fileutils.ensure_tree(recycle)
        cmd = ('mv', mounted_path, recycle)
        processutils.execute(*cmd, run_as_root=True)

    def ensure_export(self, ctx, volume):
        """Synchronously recreates an export for a logical volume."""
        pass
        #self._ensure_share_mounted(volume['provider_location'])

    def create_export(self, ctx, volume):
        """Exports the volume. Can optionally return a Dictionary of changes
        to the volume object to be persisted."""
        pass

    def remove_export(self, ctx, volume):
        """Removes an export for a logical volume."""
        pass

    def restore_volume(self, volume, snapshot):
        volume = dict(volume)
        snapshot = dict(volume)
        volume_path = self._get_volume_path(volume['id'])
        snapshot_path = self._get_snapshot_path(snapshot['id'])
        volume_size_mb = snapshot['volume_size'] * 1024

        cmd = ("dd", 'if=%s'%snapshot_path, 'of=%s'%volume_path, 'bs=1M', 'count=%d'%volume_size_mb)
        self._execute(*cmd, run_as_root=True)

    def create_snapshot(self, snapshot_ref):
        """Creates a snapshot of a volume."""
        snapshot = dict(snapshot_ref) 

        if not self._have_enough_space(snapshot['volume_size']):
            msg=(_("Cann't create the volume snapshot, without enough space on pofs storage"))
            LOG.error(msg)
            raise

        volume_path = self._get_volume_path(snapshot['volume_id'])
        snapshot_path = self._get_snapshot_path(snapshot['id'])
        volume_size_mb = snapshot['volume_size'] * 1024

        cmd = ("dd", 'if=%s'%volume_path, 'of=%s'%snapshot_path, 'bs=1M', 'count=%d'%volume_size_mb)
        self._execute(*cmd, run_as_root=True)

#        self._execute('qemu-img', 'snapshot', '-c' , snapshot['id'], volume_path, run_as_root=True)
#        self._execute('qemu-img', 'convert', '-f', volume_fmt, '-O', snapshot_fmt, '-s', snapshot['id'], volume_path, snapshot_path)

#        ret = self._execute('qemu-img', 'snapshot', '-l', volume_path, run_as_root=True)
#        if snapshot['id'] in ret:
#           self._execute('qemu-img', 'snapshot', '-d' , snapshot['id'], volume_path, run_as_root=True)

    def delete_snapshot(self, snapshot_ref):
        """delete a snapshot"""
        snapshot = dict(snapshot_ref)
        snapshot_path = self._get_snapshot_path(snapshot['id'])
        if os.path.exists(snapshot_path):
            recycle = self.recycle_path()
            fileutils.ensure_tree(recycle)
            cmd = ('mv', snapshot_path, recycle)
            processutils.execute(*cmd, run_as_root=True)
        LOG.info("Deleted snapshot %s"%snapshot['id'])
 
    def create_cloned_volume(self, volume, src_vref):
        """Creates a clone of the specified volume."""
        LOG.info(_('Creating clone of volume: %s') % src_vref['id'])

    def backup_volume(self, context, backup, backup_service):
        """Create a new backup from an existing volume."""
        volume = self.db.volume_get(context, backup['volume_id'])
        volume_file = self.local_path(volume)
        backup_service.backup(backup, volume_file)

    def restore_backup(self, context, backup, volume, backup_service):
        """Restore an existing backup to a new or existing volume."""
        volume_file = self.local_path(volume)
        backup_service.restore(backup, volume['id'], volume_file)

    def initialize_connection(self, volume, connector):
        """Allow connection to connector and return connection info."""
        data = {'export': volume['provider_location'],
                'name': volume['name']}
        return {
            'driver_volume_type': self.configuration.default_volume_type or 'pofs',
            'data': data
        }

    def terminate_connection(self, volume, connector, **kwargs):
        """Disallow connection from connector"""
        pass

    def _get_snapshot_path(self, snapshot_id):
        md=int(hashlib.md5(snapshot_id).hexdigest(), 16)%100
        snap_path=os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_snapshot_directory)
        return os.path.join(snap_path, str(md), 'snapshot-%s'%snapshot_id)

    def _get_volume_path(self, volume_id):
        md=int(hashlib.md5(volume_id).hexdigest(), 16)%100
        ebs_path=os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_volume_directory)
        return os.path.join(ebs_path, str(md), 'volume-%s'%volume_id)

    def _get_volume_location(self, volume_id):
        md=int(hashlib.md5(volume_id).hexdigest(), 16)%100
        ebs_path=os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_volume_directory) 
        return os.path.join(ebs_path, str(md))
  
    def recycle_path(self):
        path = os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_volume_directory, 'recycle')
        return path
        
    def _get_space_info(self):
        if not self._path_exists(self.configuration.pofs_mount_point):
           msg=(_("Cann't get space information of pofs storage form %s , without pofs storage mount ?"%(self.configuration.pofs_mount_point))) 
           LOG.error(msg)
           raise
        try:
           vfs=os.statvfs(self.configuration.pofs_mount_point)
        except Exception, ex:
           msg=(_("Failed get space inforamtion of pofs storage from %s , %s : %s"%(self.configuration.pofs_mount_point, Exception, ex)))
           LOG.error(msg)
           raise

        total = vfs[statvfs.F_BLOCKS]*vfs[statvfs.F_BSIZE]/(1024*1024*1024)
        avil  = vfs[statvfs.F_BAVAIL]*vfs[statvfs.F_BSIZE]/(1024*1024*1024)
        free  = vfs[statvfs.F_BFREE]*vfs[statvfs.F_BSIZE]/(1024*1024*1024)
        used  = total - free
        percentage = 100*(total - avil)/total

        return (total, used, avil, percentage) 

    def _have_enough_space(self, size):
        """ Check if there have space on pofs storage """
        total, used, free, usage = self._get_space_info()   

        if (100-usage) < CONF.ebs_reserved_percentage:
           return false;
     
        return True

    def _do_create_volume(self, volume):
        """Create a volume on given storage path
        :param volume: volume reference
        """
        volume_path = self.local_path(volume)
        volume_size = volume['size']

        msg = (_("Volume path: %s."%volume_path))
        if os.path.exists(volume_path):
            msg = (_("Volume %s already exists."%volume['name']))
            LOG.info(msg) 
            return 

        if not self._have_enough_space(volume_size):
            msg=(_("Cann't create the volume, without enough space on pofs storage"))
            LOG.error(msg)
            raise

        if self.configuration.using_sparsed_format:
            self._create_sparsed_file(volume_path, volume_size)
        else:
            self._create_regular_file(volume_path, volume_size)
 
        self._set_rw_permissions_for_all(volume_path)
        msg=(_("cinder-volume ebs successed created volume %s"%volume_path))   
        LOG.info(msg)

    def _test_ebs_rw(self):
        un = uuid.uuid4()
        vol_path = os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_volume_directory)
        fname=os.path.join(vol_path, "ebs_rw.test.%s"%un)
        try:
            fobj = open(fname, 'w') 
            wtest_txt = u'The txt is pofs rw test content, when you see this passage, it mean the pofs storage service is normaly'
            fobj.write(wtest_txt)
            fobj.close()
        except Exception, ex:
            msg=(_("Failed to save data to pofs storage for pofs write test, %s : %s"%(Exception,ex)))
            LOG.error(msg)
            raise

        try:
            fobj = open(fname, 'r')  
            rtest_txt = fobj.read()
            fobj.close()
        except Exception, ex:
            msg=(_("Failed to read data from pofs storage for pofs read test, %s : %s"%(Exception,ex)))
            LOG.error(msg)
            raise
         
        if cmp(wtest_txt, rtest_txt) is not 0:
           msg=(_("Failed for pofs storage rw test , get disaccord data for test"))
           LOG.error(msg)
           raise 
       
        msg=(_("POFS storage rw passed"))
        LOG.info(msg)
        
        self._execute('rm', '-f', fname)

    def _ensure_ebs_exist(self):
        """Look for EBS storage mounted, and directroy created"""
        ebs_path = os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_volume_directory)
        for i in range(0, 100):
            fileutils.ensure_tree(os.path.join(ebs_path, str(i)))

        snap_path = os.path.join(self.configuration.pofs_mount_point, self.configuration.ebs_snapshot_directory)
        for i in range(0, 100):
            fileutils.ensure_tree(os.path.join(snap_path, str(i)))

    def get_volume_stats(self, refresh=False):
        """Get volume status.

        If 'refresh' is True, run update the stats first."""
        if refresh or not self._stats:
            self._update_volume_status()

        return self._stats

    def _update_volume_status(self):
        """Retrieve status info from volume group."""

        LOG.debug(_("Updating volume status"))
        data = {}
        #backend_name = self.configuration.safe_get('volume_backend_name')
        data["volume_backend_name"] ='Generic_POFS' #backend_name or 'Generic_NFS'
        data["vendor_name"] = 'Open Source'
        data["driver_version"] = '1.0'
        data["storage_protocol"] = 'pofs'
        data["availability_zone"] = self.configuration.safe_get('storage_availability_zone')
        data["volume_type"] = self.configuration.safe_get('default_volume_type')

        self._test_ebs_rw()
        
        total_gb, used_gb, avail_gb, percentage = self._get_space_info()
        LOG.info(_("Update POFS storage status total:%dGB  used:%dGB  avail:%dGB  usage:%d%%"%(total_gb, used_gb, avail_gb, percentage)))
        data['total_capacity_gb'] = total_gb
        data['free_capacity_gb'] = avail_gb
        data['reserved_percentage'] = self.configuration.ebs_reserved_percentage
        data['QoS_support'] = False
        CONF.max_gigabytes = total_gb
        self._stats = data
