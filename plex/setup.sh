apt update && apt upgrade -y
apt install build-essential pve-headers-$(uname -r) nfs-common -y

wget https://downloads.plex.tv/plex-media-server-new/1.41.6.9685-d301f511a/debian/plexmediaserver_1.41.6.9685-d301f511a_amd64.deb?_gl=1*jfnm07*_gcl_au*NTg4NTgyOTcyLjE3NDU3NDExNzI.*_ga*NTYwNzY1OTAxLjE3NDU3NDA1MjA.*_ga_G6FQWNSENB*MTc0NTk5OTM2NC40LjEuMTc0NTk5OTM4MC40NC4wLjA.

dpkg -i plexmediaserver_1.41.6.9685-d301f511a_amd64.deb?_gl=1*jfnm07*_gcl_au*NTg4NTgyOTcyLjE3NDU3NDExNzI.*_ga*NTYwNzY1OTAxLjE3NDU3NDA1MjA.*_ga_G6FQWNSENB*MTc0NTk5OTM2NC40LjEuMTc0NTk5OTM4MC40NC4wLjA.

nano /etc/fstab

# add this
# 10.0.100.30:/mnt/main/usr/plex /nfs/plex nfs defaults 0 0

systemctl dameon-reload

# mount nfs
mount -a

# install drivers
chmod +x ./NVIDIA.run
./NVIDIA.run --no-kernel-modules


