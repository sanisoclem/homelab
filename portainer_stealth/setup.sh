# Ensure eth0 has the correct VLAN tag

apt update && apt upgrade -y

apt install nfs-common -y

# https://docs.docker.com/engine/install/debian/#install-using-the-repository
apt install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update

apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

docker run hello-world

# create nfs volumes
# note: NFS share should whitelist stealth VLAN subnet (e.g., 10.0.123.0/24)
# also need to whitelist traffic from stealth VLAN to NAS IP, if blocked
docker volume create --driver local \
  --opt type=nfs \
  --opt o=addr=10.0.100.30,rw,nfsvers=4,proto=tcp \
  --opt device=:/mnt/main/svc/portainer_stealth \
  portainer_data

docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:lts
