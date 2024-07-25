# Configure networking #
###
echo 'Setting static IP address for Hyper-V...'
cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - $1/24
      gateway4: 192.168.1.1
      dhcp6: false
      nameservers:
          addresses: [8.8.8.8, 4.4.4.4]
EOF

echo "sleep 90 && sudo netplan apply" >> /root/script.sh
chmod +x /root/script.sh
nohup /root/script.sh &
###

### disabled SWAP ###
sudo swapoff -a
sudo sed -i '/\tswap\t/d' /etc/fstab

### install cri-o ###
sudo apt-get update
sudo apt-get install -y software-properties-common curl
sudo curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/v1.30/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

sudo echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/v1.30/deb/ /" |
    sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update
sudo apt-get install -y cri-o
sudo systemctl start crio.service

### install KUBEAMD/KUBECTL/KUBELET ###
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm
sudo apt-mark hold kubelet kubeadm
sudo systemctl enable --now kubelet

### enabled port-forwarding ###
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1

### initiate controlplane ###
sudo [TOKEN] --discovery-token-unsafe-skip-ca-verification
