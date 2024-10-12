#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Update and upgrade the system
echo "Updating and upgrading the system..."
sudo apt-get update && sudo apt-get upgrade -y

# Install prerequisites
echo "Installing prerequisites..."
sudo apt-get install -yqq \
    curl \
    git \
    apt-transport-https \
    ca-certificates \
    gnupg-agent \
    software-properties-common \
    wireguard \
    iptables \
    tor \
    proxychains4 \
    python3-pip

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
echo "Installing Docker Compose..."
sudo pip3 install docker-compose

# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf'
sudo sysctl -p

# Generate WireGuard keys
echo "Generating WireGuard keys..."
umask 077
wg genkey | tee server_private_key | wg pubkey > server_public_key
wg genkey | tee client_private_key | wg pubkey > client_public_key

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
sudo mkdir -p /etc/wireguard
cat <<EOT | sudo tee /etc/wireguard/wg0.conf
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $(cat server_private_key)
SaveConfig = true

[Peer]
PublicKey = $(cat client_public_key)
AllowedIPs = 10.66.66.2/32
EOT

# Configure firewall (iptables)
echo "Configuring firewall (iptables)..."
NETWORK_IFACE=$(ip route get 1 | awk '{print $5; exit}')
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -A INPUT -i wg0 -j ACCEPT
sudo iptables -A FORWARD -i wg0 -j ACCEPT
sudo iptables -A FORWARD -o wg0 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o "$NETWORK_IFACE" -j MASQUERADE

# Save iptables rules
echo "Saving iptables rules..."
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'

# Configure Tor
echo "Configuring Tor..."
sudo sh -c 'echo "SOCKSPort 9050" >> /etc/tor/torrc'
sudo systemctl restart tor


echo "Configuring ProxyChains..."
sudo sh -c 'cat > /etc/proxychains4.conf <<EOT
dynamic_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5  127.0.0.1 9050
EOT'

# Clone Wirehole repository
echo "Cloning Wirehole repository..."
git clone https://github.com/IAmStoxe/wirehole.git
cd wirehole

# Modify docker-compose.yml to include Tor and Web UI
echo "Modifying docker-compose.yml to include Tor and Web UI..."
cat <<EOT > docker-compose.yml
version: "3"

services:
  unbound:
    image: mvance/unbound:latest
    container_name: unbound
    restart: always
    hostname: unbound
    volumes:
      - ./unbound:/opt/unbound/etc/unbound/
    networks:
      private_network:
        ipv4_address: 10.2.0.200

  wireguard:
    depends_on: [unbound, pihole]
    image: linuxserver/wireguard
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Chicago
      - SERVERURL=auto
      - SERVERPORT=51820
      - PEERS=pc1,pc2,phone1
      - PEERDNS=auto
      - INTERNAL_SUBNET=10.13.13.0
    volumes:
      - ./wireguard:/config
      - /lib/modules:/lib/modules
    ports:
      - 51820:51820/udp
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: always
    networks:
      private_network:
        ipv4_address: 10.2.0.100

  pihole:
    depends_on: [unbound]
    container_name: pihole
    image: pihole/pihole:latest
    restart: always
    hostname: pihole
    ports:
      - 53:53/tcp
      - 53:53/udp
      - 80:80/tcp
    environment:
      TZ: 'America/Chicago'
      WEBPASSWORD: 'password'
    volumes:
      - ./etc-pihole:/etc/pihole
      - ./etc-dnsmasq.d:/etc/dnsmasq.d
    dns:
      - 127.0.0.1
      - 1.1.1.1
    cap_add:
      - NET_ADMIN
    networks:
      private_network:
        ipv4_address: 10.2.0.100

  tor:
    image: dperson/torproxy
    container_name: tor
    restart: always
    ports:
      - 9050:9050
    networks:
      private_network:
        ipv4_address: 10.2.0.150

  webui:
    build: ./webui
    container_name: webui
    restart: always
    ports:
      - 8080:8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      private_network:
        ipv4_address: 10.2.0.160

networks:
  private_network:
    ipam:
      driver: default
      config:
        - subnet: 10.2.0.0/24
EOT

# Create Web UI
echo "Creating Web UI..."
mkdir -p webui
cat <<EOT > webui/Dockerfile
FROM python:3.9-slim

WORKDIR /app

RUN pip install flask docker

COPY app.py .

CMD ["python", "app.py"]
EOT

cat <<EOT > webui/app.py
from flask import Flask, render_template_string, request
import docker

app = Flask(__name__)
client = docker.from_env()

HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>WireGuard/Tor Switch</title>
</head>
<body>
    <h1>WireGuard/Tor Switch</h1>
    <form method="post">
        <input type="submit" name="action" value="Enable WireGuard">
        <input type="submit" name="action" value="Enable Tor">
    </form>
    <p>{{ message }}</p>
</body>
</html>
'''

@app.route('/', methods=['GET', 'POST'])
def index():
    message = ""
    if request.method == 'POST':
        action = request.form['action']
        if action == 'Enable WireGuard':
            client.containers.get('wireguard').restart()
            client.containers.get('tor').stop()
            message = "WireGuard enabled, Tor disabled"
        elif action == 'Enable Tor':
            client.containers.get('wireguard').stop()
            client.containers.get('tor').restart()
            message = "Tor enabled, WireGuard disabled"
    return render_template_string(HTML, message=message)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOT

# ... [Rest of the script remains the same] ...

# Additional instructions for the user
cat << EOT

Setup completed successfully! Here's what you need to know:

1. WireGuard is set up and running. You can find the client configurations in the ./wireguard/peer_pc1, ./wireguard/peer_pc2, and ./wireguard/peer_phone1 folders.

2. Pi-hole is accessible at http://$(hostname -I | awk '{print $1}')/admin
   Default password: password (change this immediately!)

3. Tor SOCKS5 proxy is available at 127.0.0.1:9050

4. To use ProxyChains with any command, prefix it with 'proxychains4'. For example:
   proxychains4 curl http://example.com

5. To stop the services, run 'docker-compose down' in the wirehole directory.

6. To start the services again, run 'docker-compose up -d' in the wirehole directory.

7. The Web UI for switching between WireGuard and Tor is available at http://$(hostname -I | awk '{print $1}'):8080

Remember to secure your Raspberry Pi by changing default passwords and keeping the system updated.
EOT
