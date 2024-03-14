# General

0. Base config (Hostname, Adapter, Firewall) use sysdm.cpl, ncpa.cpl, wf.msc
1. Add roles via 'Server Manager' (AD DS, DNS, DHCP)
2. Setup AD DS (you know how)
3. Setup DNS Forwarders
4. Setup DNS Reverse-Zone
5. Setup DHCP
6. Protected User

# DNS

0. Reverse Lookup Zones
1. Forward to LinNNS1 (192.168.30.10)

# DHCP

0. New Scope
1. Exclude addresses (10.0.0.254, 10.0.0.10)
2. DNS-Integration (Scope -> Properties -> DNS -> Enable DNS dynamic updates -> Always)

# Protected User

0. Active Directory Users and Computers -> "corp.NN.at" -> Users -> Administrator -> Properties -> Member Of -> Add -> Protected Users 