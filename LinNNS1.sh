#!/bin/bash
# Debug
if [ $EUID -ne 0 ]; then
  exit 1
fi

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
decho "installing (isc-dhcp-server bind9 dnsutils bind9-doc)"
apt -yq install --assume-yes isc-dhcp-server bind9 dnsutils bind9-doc

decho "changing hostname..."
OLD_HOST=$(hostname)
sed -i "s/$OLD_HOST/Lin${NAME}S1/g" /etc/hosts
hostnamectl hostname Lin${NAME}S1
decho "new hostname is 'Lin${NAME}S1'"

# Netplan
decho "netplan"
MAC_DMZ=$(ip -o link show ens33 | grep -oh ..:..:..:..:..:.. | head -1)
MAC_OUT=$(ip -o link show ens34 | grep -oh ..:..:..:..:..:.. | head -1)

mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
cat > /etc/netplan/00-custom.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      match:
        macaddress: ${MAC_DMZ}
      set-name: dmz
      dhcp4: false
      addresses:
        - 192.168.30.10/24
      routes:
        - to: default
          via: 192.168.30.254
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
    ens34:
      match:
        macaddress: ${MAC_OUT}
      set-name: outside
      dhcp4: true
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
EOF
netplan apply
# DHCP
decho "dhcp"
cat > /etc/dhcp/dhcpd.conf << EOF
ddns-update-style none;
authoritative;
subnet 192.168.30.0 netmask 255.255.255.0 {
        range 192.168.30.100 192.168.30.150;
        interface dmz;
        option domain-name-servers 192.168.30.10;
        option routers 192.168.30.254;
}
EOF

# DNS
decho "dns"
mkdir /var/log/named && chown bind:bind /var/log/named

cat > /etc/bind/named.conf << EOF
logging {
    channel query.log {
        file "/var/log/named/query.log";
        severity debug 3;
    };
    category queries { query.log; };
};

options {
        directory "/var/cache/bind";

        // If there is a firewall between you and nameservers you want
        // to talk to, you may need to fix the firewall to allow multiple
        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113

        // If your ISP provided one or more IP addresses for stable
        // nameservers, you probably want to use them as forwarders.
        // Uncomment the following block, and insert the addresses replacing
        // the all-0's placeholder.

        forwarders {
            8.8.8.8;
            1.1.1.1;
        };
        allow-query {any;};

        //========================================================================
        // If BIND logs error messages about the root key being expired,
        // you will need to update your keys.  See https://www.isc.org/bind-keys
        //========================================================================
        dnssec-validation auto;

        listen-on-v6 { any; };
};
EOF

# wait for ip
check_ip_address () {
    ip address show dev "dmz" | grep -q "inet "
}

decho "waiting for address on interface 'dmz'..."
while ! check_ip_address; do
    sleep 1
done
decho "got ip: '$(ip -o -4 a show lan | grep -oP '\d+(\.\d+){3}' | head -1)'"

decho "services"
systemctl enable --now named
systemctl enable --now isc-dhcp-server
decho "DONE!"
exit 0