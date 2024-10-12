#!/bin/bash

# Clone the WireHole repository from GitHub
git clone https://github.com/IAmStoxe/wirehole.git

# Change directory to the cloned repository
cd wirehole

# Update the .env file with your configuration
cp .env.example .env
nano .env  # Or use any text editor of your choice to edit the .env file

# Replace the public IP placeholder in the docker-compose.yml
sed -i "s/REPLACE_ME_WITH_YOUR_PUBLIC_IP/$(curl -s ifconfig.me)/g" docker-compose.yml

# Create the docker-compose.yml with Tor and ProxyChains functionality
cat <<EOL > docker-compose.yml
version: "3"
networks:
  private_network:
    ipam:
      driver: default
      config:
        - subnet: 10.2.0.0/24

services:
  unbound:
    image: mvance/unbound:latest
    container_name: unbound
    restart: unless-stopped
    hostname: unbound
    volumes:
      - ./unbound:/opt/unbound/etc/unbound/
    networks:
      private_network:
        ipv4_address: 10.2.0.200
    cap_add:
      - NET_ADMIN
    env_file: .env

  wireguard:
    depends_on:
      - unbound
      - pihole
    image: linuxserver/wireguard
    container_name: wireguard
    ports:
      - 5000:5000
      - 51820:51820/udp
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    volumes:
      - ./config:/config
    env_file: .env

  wireguard-ui:
    image: ngoduykhanh/wireguard-ui:latest
    container_name: wireguard-ui
    depends_on:
      - wireguard
    cap_add:
      - NET_ADMIN
    network_mode: service:wireguard
    logging:
      driver: json-file
      options:
        max-size: 50m
    volumes:
      - ./db:/app/db
      - ./config:/config
    env_file: .env

  pihole:
    depends_on:
      - unbound
    container_name: pihole
    image: pihole/pihole:latest
    restart: unless-stopped
    hostname: pihole
    dns:
      - 127.0.0.1
      - \${PIHOLE_DNS}
    volumes:
      - ./etc-pihole/:/etc/pihole/
      - ./etc-dnsmasq.d/:/etc/dnsmasq.d/
    cap_add:
      - NET_ADMIN
    networks:
      private_network:
        ipv4_address: 10.2.0.100
    env_file: ./.env

  tor:
    image: dperson/torproxy:latest
    container_name: tor
    restart: unless-stopped
    ports:
      - "9050:9050"
    networks:
      private_network:
        ipv4_address: 10.2.0.250
    environment:
      - TOR_NOEXIT=1  # Configure as a non-exit node
EOL

# Start the Docker containers
docker compose up 
