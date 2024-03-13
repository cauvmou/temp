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
apt -yq install --assume-yes openssh-client dnsutils realmd sssd sssd-tools adcli samba-common-bin 

# Set hostname
decho "changing hostname..."
OLD_HOST=$(hostname)
sed -i "s/$OLD_HOST/Lin${NAME}C2/g" /etc/hosts
hostnamectl hostname Lin${NAME}C2
decho "new hostname is 'Lin${NAME}C2'"

# Netplan
decho "netplan"
MAC_LAN=$(ip -o link show ens33 | grep -oh ..:..:..:..:..:.. | head -1)

mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
cat > /etc/netplan/00-custom.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      match:
        macaddress: ${MAC_LAN}
      set-name: lan
      dhcp4: true
EOF
netplan apply

# Domain
decho "joining domain..."
realm join corp.$NAME.at
# echo "services = nss, pam" >> /etc/sssd/sssd.conf # Unsure
pam-auth-update --enable mkhomedir

decho "DONE!"
exit