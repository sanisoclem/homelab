apt update && apt upgrade -y
apt install build-essential pve-headers-$(uname -r) -y

reboot


wget https://us.download.nvidia.com/XFree86/Linux-x86_64/570.144/NVIDIA-Linux-x86_64-570.144.run

chmod +x ./NVIDIA-Linux-x86_64-570.144.run 

./NVIDIA-Linux-x86_64-570.144.run --dkms

reboot


# list GPUs
ls /dev/nvidia*

# make sure number s(195, 234, 237) match the output of prev cmd
cat << 'EOF' >> /etc/pve/lxc/501.conf
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.cgroup2.devices.allow: c 237:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file
EOF

pct start 501

pct push  501 ./NVIDIA-Linux-x86_64-570.144.run  /root/NVIDIA.run


# ensure driver is loaded on startup
crontab -e
# @reboot nvidia-smi