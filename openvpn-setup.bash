#!/usr/bin/env bash

__txt_bold=$(tput bold)
__txt_normal=$(tput sgr0)

if [ "$(whoami)" != 'root' ]; then
	echo 'Need root privileges. Exiting.'
	exit -1
fi

echo 'Script will exit when errors occur.'
set -e
echo

_lan_ip=$(ip addr show dev eth0 | grep inet | grep -v inet6 | sed -e "s/.*inet //" | sed -e "s/\/.*//")
if [ -z "$_lan_ip" ]; then
	exit
fi
_password=$(curl -s "https://www.random.org/passwords/?num=1&len=16&format=plain&rnd=new")
_done='n'
_domain=''
_wan_ip=''
_int_port=''
_ext_port=''
while [ $_done == 'n' ]
do
	read -p "What domain do you want to push clients into? [example.local]: " _domain
	read -p "Which remote will clients be connecting to? [0.0.0.0]: " _wan_ip
	read -p "Which port do you want the OpenVPN service to use? [1234]: " _int_port
	read -p "At which port do you want OpenVPN to be accessible from the outside? [4321]: " _ext_port
	read -p "Are you satisfied with this configuration? [y/N]: " _done
	echo
	if [ -z "$_done" ]; then
		_done='n'
	fi
	if [ "$_done" == 'N' ]; then
		_done='n'
	fi
done

if [ -z "$_domain" ]; then
	_domain="example.local"
fi
if [ -z "$_wan_ip" ]; then
	_wan_ip="0.0.0.0"
fi
if [ -z "$_int_port" ]; then
	_int_port=1234
fi
if [ -z "$_ext_port" ]; then
	_ext_port=4321
fi

echo 'Updating system (this may take some time)...'
echo '* Updating package lists...'
apt-get update > /dev/null 2>&1
echo '* Updating packages in place...'
apt-get upgrade -y > /dev/null 2>&1
echo '* Updating packages including dependencies...'
apt-get dist-upgrade -y > /dev/null 2>&1
echo '* Removing obsolete packages...'
apt-get autoremove -y > /dev/null 2>&1
echo '* Cleaning up local repository...'
apt-get autoremove -y > /dev/null 2>&1
echo
echo 'Setting up OpenVPN server...'
echo '* Installing OpenVPN...'
apt-get install openvpn easy-rsa zip -y > /dev/null 2>&1

echo '* Configuring security...'
mkdir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa/* .
sed -i -e 's/KEY_COUNTRY=.*/KEY_COUNTRY="REPLACE_COUNTRY"/g' ./vars
sed -i -e 's/KEY_PROVINCE=.*/KEY_PROVINCE="REPLACE_PROVINCE"/g' ./vars
sed -i -e 's/KEY_CITY=.*/KEY_CITY="REPLACE_CITY"/g' ./vars
sed -i -e 's/KEY_ORG=.*/KEY_ORG="REPLACE_ORG"/g' ./vars
sed -i -e 's/KEY_EMAIL=.*/KEY_EMAIL="REPLACE_EMAIL"/g' ./vars
sed -i -e 's/KEY_OU=.*/KEY_OU="REPLACE_OU"/g' vars
source ./vars > /dev/null 2>&1
./clean-all > /dev/null 2>&1
./build-dh > /dev/null 2>&1
./pkitool --initca > /dev/null 2>&1 # TODO enable utf-8 for üs
./pkitool --server server > /dev/null 2>&1
cd keys
openvpn --genkey --secret ta.key > /dev/null 2>&1
cp server.crt server.key ca.crt dh2048.pem ta.key /etc/openvpn/
mkdir "$HOME/OpenVPN $_domain"
cp ca.crt ta.key "$HOME/OpenVPN $_domain"

echo '* Configuring OpenVPN server...'
cd /etc/openvpn/easy-rsa
#./pkitool client1 # for client certificate authentication
cat > /etc/openvpn/server.conf <<- EndOfFile
## basic openvpn config
local $_lan_ip
port $_int_port
dev tun
proto udp
comp-lzo
max-clients 50

## certs and tunnel security
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
tls-auth ta.key 0
cipher AES-128-CBC

## openvon daemon security
ifconfig-pool-persist ipp.txt
user nobody
group nogroup
persist-key
persist-tun

## connection client/ip/traffic config
server 10.8.0.0 255.255.255.0
client-to-client
keepalive 10 120

## logging options
status /var/log/openvpn/openvpn-status.log
log-append  /var/log/openvpn/openvpn.log
verb 4 # 4 is considered standard for this setting, 6 is a bit verbose, 9 is max.
mute 5

## route all traffic through vpn
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $(grep nameserver /etc/resolv.conf | head -1)"
push "dhcp-option DOMAIN $_domain"
push "route 10.8.0.0 255.255.0.0"
push "route 10.8.0.0 255.255.255.0"
push "route $(echo "${_lan_ip%.*}".0) 255.255.255.0"
client-to-client

## disable cert authentication
client-cert-not-required
duplicate-cn

## plugins
## LDAP (Active Directory authentication) plugin
#plugin /usr/lib/openvpn/openvpn-auth-ldap.so /etc/openvpn/auth/auth-ldap.conf
plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so openvpn
EndOfFile

echo '* Configuring authentication...'
useradd -p "$_password" ovpn
groupadd vpn
usermod -a -G vpn ovpn
cat > /etc/pam.d/openvpn <<- EndOfFile
auth    required        pam_unix.so             shadow nodelay
auth    requisite       pam_succeed_if.so       uid >= 500 quiet
auth    requisite       pam_succeed_if.so       user ingroup vpn quiet
auth    required        pam_tally2.so           deny=64 even_deny_root unlock_time=1200
account required        pam_unix.so
EndOfFile

echo '* Configuring firewall...'
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$(ifconfig | grep 'encap:Ethernet' | sed -e 's/ .*//g')" -j MASQUERADE
iptables -A INPUT -i tun+ -j ACCEPT
iptables-save > /etc/network/iptables.conf
echo 'post-up iptables-restore < /etc/network/iptables.conf' >> /etc/network/interfaces

echo '* Configuring system...'
chmod 644 /etc/openvpn/server.conf
mkdir /var/log/openvpn
echo "ip_tables\nipt_MASQUERADE" >> /etc/modules
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
service openvpn restart > /dev/null 2>&1 # preliminary restart because why not

echo 'Creating client config...'
cd; cd "OpenVPN $_domain"
mv ca.crt "$_domain.ca.crt"
mv ta.key "$_domain.ta.key"
cat > "$_domain.userpass.txt" <<- EndOfFile
ovpn
$_password
EndOfFile
cat > "$_domain.ovpn" <<- EndOfFile
remote $_wan_ip
port $_ext_port
proto udp
client
float
dev tun
ca $_domain.ca.crt
remote-cert-tls server
tls-auth $_domain.ta.key 1
cipher AES-128-CBC
comp-lzo
ping 10
persist-tun
persist-key
verb 4

#AD/PASSWORD AUTHENTICATION
auth-user-pass $_domain.userpass.txt
auth-nocache
EndOfFile
echo zip ../OpenVPN\ "$_domain".zip ./* > /dev/null 2>&1
zip ../OpenVPN\ "$_domain".zip ./* > /dev/null 2>&1
cd
rm -rf ./OpenVPN\ $_domain

echo 'Done!'

echo
echo '### REMINDER ###'
echo
echo "Do not forget to enable ${__txt_bold}port forwarding${__txt_normal}."
echo "Forward port $_ext_port on NIC $_wan_ip to port $_int_port on this machine ($_lan_ip)."
echo
echo "Make sure there is a ${__txt_bold}route${__txt_normal} in place for the 10.8.0.0/24 network."
echo "Its gateway is this server (again, $_lan_ip)."
echo
echo "For configuring clients, simply copy the contents of ~/OpenVPN $_domain.zip to the .../config directory of your preferred OpenVPN client solution."
echo
echo "Please ${__txt_bold}reboot the server now${__txt_normal} to apply all changes."

