# MAC bc:24:11:b7:76:30
apt update && apt upgrade -y

apt install nfs-common -y

# https://docs.docker.com/engine/install/debian/#install-using-the-repository
apt install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update

apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

chmod +x ./NVIDIA.run
./NVIDIA.run --no-kernel-modules

docker run hello-world

# create nfs volumes
docker volume create --driver local \
  --opt type=nfs \
  --opt o=addr=10.0.100.30,rw,nfsvers=4,proto=tcp \
  --opt device=:/mnt/main/svc/portainer \
  portainer_data

docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:lts
