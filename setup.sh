#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Detect package manager
if command -v pacman &> /dev/null
then
    PM="pacman"
    SUDO="sudo"
elif command -v apt &> /dev/null
then
    PM="apt"
    SUDO="sudo"
elif command -v dnf &> /dev/null
then
    PM="dnf"
    SUDO="sudo"
else
    echo "Unsupported package manager. Only pacman, apt, and dnf are supported."
    exit 1
fi

# Backup current network configuration
echo "Backing up current network configuration..."
mkdir -p /etc/network-config-backup
$SUDO cp -r /etc/netctl /etc/network-config-backup/netctl.backup 2>/dev/null || true
$SUDO cp -r /etc/NetworkManager/system-connections /etc/network-config-backup/nm.backup 2>/dev/null || true
$SUDO cp -r /etc/systemd/network /etc/network-config-backup/systemd-network.backup 2>/dev/null || true
$SUDO cp /etc/resolv.conf /etc/network-config-backup/resolv.conf.backup 2>/dev/null || true

# Update mirror list or update package list
if [ "$PM" == "pacman" ]; then
    echo "Updating mirror list..."
    $SUDO pacman -Sy reflector --noconfirm
    $SUDO reflector --country 'INDIA' --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
elif [ "$PM" == "apt" ]; then
    echo "Updating package list..."
    $SUDO apt update
elif [ "$PM" == "dnf" ]; then
    echo "Updating package list..."
    $SUDO dnf makecache
fi

# Ensure DNS configuration
echo "Configuring DNS..."
$SUDO chattr -i /etc/resolv.conf
$SUDO sh -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'
$SUDO sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
$SUDO chattr +i /etc/resolv.conf

# Update the system
echo "Updating system..."
if [ "$PM" == "pacman" ]; then
    $SUDO pacman -Syu --noconfirm
elif [ "$PM" == "apt" ]; then
    $SUDO apt upgrade -y
elif [ "$PM" == "dnf" ]; then
    $SUDO dnf upgrade -y
fi

# Install necessary packages
echo "Installing necessary packages..."
if [ "$PM" == "pacman" ]; then
    $SUDO pacman -S --noconfirm wireguard-tools tor proxychains-ng docker python-pip
elif [ "$PM" == "apt" ]; then
    $SUDO apt install -y wireguard tor proxychains4 docker.io python3-pip
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
elif [ "$PM" == "dnf" ]; then
    $SUDO dnf install -y wireguard-tools tor proxychains-ng docker python3-pip
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
fi

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
$SUDO sysctl -w net.ipv4.ip_forward=1
$SUDO sh -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf'
$SUDO sysctl -p

# Start WireGuard
echo "Starting WireGuard..."
$SUDO wg-quick up wg0
$SUDO systemctl enable wg-quick@wg0

# Configure firewall (iptables)
echo "Configuring firewall (iptables)..."
$SUDO iptables -A INPUT -p udp --dport 51820 -j ACCEPT
$SUDO iptables -A INPUT -i wg0 -j ACCEPT
$SUDO iptables -A FORWARD -i wg0 -j ACCEPT
$SUDO iptables -A FORWARD -o wg0 -j ACCEPT
$SUDO iptables -t nat -A POSTROUTING -o $(ip route get 1 | awk '{print $5;exit}') -j MASQUERADE
$SUDO iptables-save | $SUDO tee /etc/iptables/rules.v4

# Install and configure Tor
echo "Installing and configuring Tor..."
if [ "$PM" == "pacman" ]; then
    $SUDO pacman -S --noconfirm tor
elif [ "$PM" == "apt" ]; then
    $SUDO apt install -y tor
elif [ "$PM" == "dnf" ]; then
    $SUDO dnf install -y tor
fi
$SUDO systemctl enable tor
$SUDO systemctl start tor

# Configure Tor
echo "Configuring Tor..."
$SUDO sh -c 'echo "SOCKSPort 9050" >> /etc/tor/torrc'
$SUDO systemctl restart tor

# Install and configure ProxyChains
echo "Installing and configuring ProxyChains..."
if [ "$PM" == "pacman" ]; then
    $SUDO pacman -S --noconfirm proxychains-ng
elif [ "$PM" == "apt" ]; then
    $SUDO apt install -y proxychains4
elif [ "$PM" == "dnf" ]; then
    $SUDO dnf install -y proxychains-ng
fi

# Configure ProxyChains
echo "Configuring ProxyChains..."
$SUDO sh -c 'cat > /etc/proxychains.conf <<EOT
dynamic_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5  127.0.0.1 9050
EOT'

# Install and configure Docker and Pi-hole
echo "Installing and configuring Docker and Pi-hole..."
if [ "$PM" == "pacman" ]; then
    $SUDO pacman -S --noconfirm docker
elif [ "$PM" == "apt" ]; then
    $SUDO apt install -y docker.io
elif [ "$PM" == "dnf" ]; then
    $SUDO dnf install -y docker
fi
$SUDO systemctl start docker
$SUDO systemctl enable docker

# Pull Pi-hole Docker image
$SUDO docker pull pihole/pihole:latest

# Run Pi-hole container
echo "Running Pi-hole container..."
$SUDO docker run -d \
  --name pihole \
  -e TZ="Asia/Kolkata" \
  -e WEBPASSWORD="himu1234" \
  -v "$(pwd)/pihole/etc-pihole:/etc/pihole" \
  -v "$(pwd)/pihole/etc-dnsmasq.d:/etc/dnsmasq.d" \
  -p 53:53/tcp -p 53:53/udp -p 80:80 \
  --restart=unless-stopped \
  pihole/pihole:latest

# Configure DNS to use Pi-hole
echo "Configuring DNS to use Pi-hole..."
$SUDO chattr -i /etc/resolv.conf
$SUDO sh -c 'echo "nameserver 127.0.0.1" > /etc/resolv.conf'
$SUDO chattr +i /etc/resolv.conf

# Configure iptables for DNS
echo "Configuring iptables for DNS..."
$SUDO iptables -A INPUT -p tcp --dport 53 -j ACCEPT
$SUDO iptables -A INPUT -p udp --dport 53 -j ACCEPT
$SUDO iptables -A INPUT -p tcp --dport 80 -j ACCEPT
$SUDO iptables -A INPUT -p udp --dport 80 -j ACCEPT
$SUDO iptables-save | $SUDO tee /etc/iptables/rules.v4

# Display status
echo "Verifying setup..."

# Verify WireGuard
$SUDO wg show

# Verify Tor
curl --socks5 127.0.0.1:9050 http://check.torproject.org

# Verify ProxyChains
proxychains curl http://check.torproject.org

# Verify Pi-hole
echo "Pi-hole is running. Access it at http://<YOUR_SERVER_IP>/admin with the password you set."

echo "Setup complete!"
