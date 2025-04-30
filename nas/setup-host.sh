apt update && apt upgrade -y
apt install nfs-common -y

# list Disks
ls /dev/disk/by-id 


# passthrough disks
qm set 101 -scsi1 /dev/disk/by-id/{REPLACE_WITH_DISK_ID}
qm set 101 -scsi2 /dev/disk/by-id/{REPLACE_WITH_DISK_ID}


