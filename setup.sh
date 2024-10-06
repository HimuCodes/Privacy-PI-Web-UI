#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Backup current network configuration
echo "Backing up current network configuration..."
mkdir -p /etc/network-config-backup
cp -r /etc/netctl /etc/network-config-backup/netctl.backup 2>/dev/null || true
cp -r /etc/NetworkManager/system-connections /etc/network-config-backup/nm.backup 2>/dev/null || true
cp -r /etc/systemd/network /etc/network-config-backup/systemd-network.backup 2>/dev/null || true
cp /etc/resolv.conf /etc/network-config-backup/resolv.conf.backup 2>/dev/null || true

# Update mirror list using reflector
echo "Updating mirror list..."
sudo pacman -Sy reflector
sudo reflector --country 'INDIA' --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

# Ensure DNS configuration
echo "Configuring DNS..."
sudo chattr -i /etc/resolv.conf
sudo sh -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'
sudo sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
sudo chattr +i /etc/resolv.conf

# Update the system
echo "Updating system..."
sudo pacman -Syu --noconfirm

# Install necessary packages
echo "Installing necessary packages..."
sudo pacman -S --noconfirm wireguard-tools tor proxychains-ng docker python-pip

# Generate WireGuard keys
echo "Generating WireGuard keys..."
umask 077
wg genkey | tee server_private_key | wg pubkey > server_public_key
wg genkey | tee client_private_key | wg pubkey > client_public_key

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
cat <<EOT > /etc/wireguard/wg0.conf
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $(cat server_private_key)
SaveConfig = true

[Peer]
PublicKey = $(cat client_public_key)
AllowedIPs = 10.66.66.2/32
EOT

# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf'
sudo sysctl -p

# Start WireGuard
echo "Starting WireGuard..."
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0

# Configure firewall (iptables)
echo "Configuring firewall (iptables)..."
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -A INPUT -i wg0 -j ACCEPT
sudo iptables -A FORWARD -i wg0 -j ACCEPT
sudo iptables -A FORWARD -o wg0 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Install and configure Tor
echo "Installing and configuring Tor..."
sudo pacman -S --noconfirm tor
sudo systemctl enable tor
sudo systemctl start tor

# Configure Tor
echo "Configuring Tor..."
sudo sh -c 'echo "SOCKSPort 9050" >> /etc/tor/torrc'
sudo systemctl restart tor

# Install and configure ProxyChains
echo "Installing and configuring ProxyChains..."
sudo pacman -S --noconfirm proxychains-ng

# Configure ProxyChains
echo "Configuring ProxyChains..."
sudo sh -c 'cat > /etc/proxychains.conf <<EOT
dynamic_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5  127.0.0.1 9050
EOT'
sudo systemctl restart proxychains-ng

# Install and configure Docker and Pi-hole
echo "Installing and configuring Docker and Pi-hole..."
sudo pacman -S --noconfirm docker
sudo systemctl start docker
sudo systemctl enable docker

# Pull Pi-hole Docker image
sudo docker pull pihole/pihole:latest

# Run Pi-hole container
echo "Running Pi-hole container..."
sudo docker run -d \
  --name pihole \
  -e TZ="ASIA/KOLKATA" \
  -e WEBPASSWORD="himu1234" \
  -v "$(pwd)/pihole/etc-pihole:/etc/pihole" \
  -v "$(pwd)/pihole/etc-dnsmasq.d:/etc/dnsmasq.d" \
  -p 53:53/tcp -p 53:53/udp -p 80:80 \
  --restart=unless-stopped \
  pihole/pihole:latest

# Configure DNS to use Pi-hole
echo "Configuring DNS to use Pi-hole..."
sudo chattr -i /etc/resolv.conf
sudo sh -c 'echo "nameserver 127.0.0.1" > /etc/resolv.conf'
sudo chattr +i /etc/resolv.conf

# Configure iptables for DNS
echo "Configuring iptables for DNS..."
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 80 -j ACCEPT
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Display status
echo "Verifying setup..."

# Verify WireGuard
sudo wg show

# Verify Tor
curl --socks5 127.0.0.1:9050 http://check.torproject.org

# Verify ProxyChains
proxychains curl http://check.torproject.org

# Verify Pi-hole
echo "Pi-hole is running. Access it at http://<YOUR_SERVER_IP>/admin with the password you set."

echo "Setup complete!"
