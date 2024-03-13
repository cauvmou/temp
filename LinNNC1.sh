#!/bin/bash
# Debug
sudo su -
set -x
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
decho "installing (openssh-client dnsutils)"
apt -yq install --assume-yes openssh-client dnsutils

# Set hostname
decho "changing hostname..."
OLD_HOST=$(hostname)
sed -i "s/$OLD_HOST/Lin${NAME}C1/g" /etc/hosts
hostnamectl hostname Lin${NAME}C1
decho "new hostname is 'Lin${NAME}C1'"

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
      dhcp4: true
    ens34:
      match:
        macaddress: ${MAC_OUT}
      set-name: outside
      dhcp4: true
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
EOF
netplan apply
decho "DONE!"
exit