#!/bin/bash
# Debug
set +x

# Run as root
sudo su -

# Update + Package install
export DEBIAN_FRONTEND=noninteractive
apt upgrade
apt -yq update
apt -yq install tmux openssh-client openssh-server iptables-persistent conntrack

# Set hostname
OLD_HOST=$(hostname)
sed -i "s/$OLD_HOST/LinNNS2/g" /etc/hosts
hostnamectl hostname LinNNS2

# Enable routing
sed -i "/^#.*ip_forward/s/^#\s*//" /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

MAC_OUT=$(ip -o link show ens33 | grep -oh ..:..:..:..:..:.. | head -1)
MAC_LAN=$(ip -o link show ens34 | grep -oh ..:..:..:..:..:.. | head -1)
MAC_DMZ=$(ip -o link show ens35 | grep -oh ..:..:..:..:..:.. | head -1)

# Netplan
mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
echo <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      match:
        macaddress: ${MAC_OUT}
      set-name: outside
      dhcp4: true
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
    ens34:
      match:
        macaddress: ${MAC_LAN}
      set-name: lan
      addresses:
        - 10.0.0.254/24
      dhcp4: false
    ens35:
      match:
        macaddress: ${MAC_DMZ}
      set-name: dmz
      addresses:
        - 192.168.30.254/24
      dhcp4: false
EOF > /etc/netplan/00-custom.yaml

# Iptables
IPT="/sbin/iptables"

# Flush und Löschen der Custom-Chains
$IPT -F
$IPT -X

# Policy setzen
$IPT -P INPUT ACCEPT
$IPT -P OUTPUT ACCEPT
$IPT -P FORWARD DROP

# Eigene Chains anlegen
$IPT -N lan_dmz
$IPT -N lan_ext
$IPT -N dmz_ext

# LAN <-> DMZ
$IPT -A FORWARD -i lan -o dmz -j lan_dmz
$IPT -A FORWARD -i dmz -o lan -j lan_dmz

$IPT -A lan_dmz -m conntrack --ctstate RELATED,ESTABLISHED -j LOG --log-prefix "IPTABLES CONN RELATED/ESTABLISHED: "
$IPT -A lan_dmz -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPT -A lan_dmz -p icmp -j ACCEPT
$IPT -A lan_dmz -p tcp --dport domain -j ACCEPT
$IPT -A lan_dmz -p udp --dport domain -j ACCEPT
$IPT -A lan_dmz -j REJECT

# LAN <-> INTERNET
$IPT -A FORWARD -i lan -o outside -j lan_ext
$IPT -A FORWARD -i outside -o lan -j lan_ext

$IPT -A lan_ext -j ACCEPT

# DMZ <-> INTERNET
$IPT -A FORWARD -i dmz -o outside -j dmz_ext
$IPT -A FORWARD -i outside -o dmz -j dmz_ext

$IPT -A dmz_ext -m conntrack --ctstate RELATED,ESTABLISHED -j LOG --log-prefix "IPTABLES CONN RELATED/ESTABLISHED: "
$IPT -A dmz_ext -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPT -A dmz_ext -p udp --dport ntp -j ACCEPT
$IPT -A dmz_ext -p tcp --dport ssh -j ACCEPT
$IPT -A dmz_ext -p tcp --dport domain -j ACCEPT
$IPT -A dmz_ext -p udp --dport domain -j ACCEPT
$IPT -A dmz_ext -p icmp -j ACCEPT
$IPT -A dmz_ext -j REJECT

# MASQUERADING
$IPT -t nat -A POSTROUTING -o outside -j MASQUERADE