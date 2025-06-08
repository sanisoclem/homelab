apt update && apt upgrade -y
apt install nfs-common -y

# list Disks
ls /dev/disk/by-id 


# passthrough disks
qm set 101 -scsi1 /dev/disk/by-id/ata-WDC_WD40EZAX-22C8UB0_WD-WX62DA45L449
qm set 101 -scsi2 /dev/disk/by-id/ata-WDC_WD40EZAX-22C8UB0_WD-WX62DA45LE9L
qm set 101 -scsi3 /dev/disk/by-id/ata-CT500BX500SSD1_2416E8A83238
qm set 101 -scsi4 /dev/disk/by-id/ata-CT500BX500SSD1_2416E8A83957