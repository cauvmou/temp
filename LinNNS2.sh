#!/bin/bash
# Debug
sudo su -
set +x
COL_DEB='\033[1;32m'
COL_NON='\033[0m'

decho () {
  echo -e "${COL_DEB}[$(date '+%Y-%m-%d %T.%4N')]-[DEBUG]:${COL_NON} $@"
}

echo -n -e "${COL_DEB}Name: ${COL_NON}"
read NAME

# Update + Package install
export DEBIAN_FRONTEND=noninteractive
decho "updating packages"
apt -yq update --assume-yes
apt -yq upgrade --assume-yes
decho "installing (tmux openssh-client openssh-server iptables-persistent conntrack)"
apt -yq install --assume-yes tmux openssh-client openssh-server iptables-persistent conntrack

# Set hostname
decho "changing hostname..."
OLD_HOST=$(hostname)
sed -i "s/$OLD_HOST/Lin${NAME}S2/g" /etc/hosts
hostnamectl hostname Lin${NAME}S2
decho "new hostname is 'Lin${NAME}S2'"

# Enable routing
decho "routing"
sed -i "/^#.*ip_forward/s/^#\s*//" /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

decho "netplan"
MAC_OUT=$(ip -o link show ens33 | grep -oh ..:..:..:..:..:.. | head -1)
MAC_LAN=$(ip -o link show ens34 | grep -oh ..:..:..:..:..:.. | head -1)
MAC_DMZ=$(ip -o link show ens35 | grep -oh ..:..:..:..:..:.. | head -1)

# Netplan
mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
cat > /etc/netplan/00-custom.yaml <<EOF
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
EOF

# Iptables
decho "configuring iptables..."
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

# Save
decho "saving iptables..."
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
decho "DONE!"
exit