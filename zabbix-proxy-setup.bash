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
_done='n'
while [ $_done == 'n' ]
do
	if [ "$__loop_err" = 'y' ]; then
		echo 'Please enter name, gateway and DNS server now.'
		echo
	fi
	read -p "Please enter a hostname prefix ('abc' will generate 'abc-zabbix-proxy' as hostname): " _namefix
	read -p "Which IP to you want the zabbix-proxy to use? [$_lan_ip]: " _lan_ip
	read -p "What's the netmask for this network? [255.255.255.0]: " _netmask
	read -p "At what IP is the gateway of this network situated? " _gw_ip
	read -p "Please enter at least one DNS nameserver (separate with spaces): " _dns_servers
	read -p "Are you satisfied with this configuration? [y/N]: " _done
	if [ -z "$_namefix" ]; then
		_done='n'
		__loop_err='y'
	fi
	if [ -z "$_gw_ip" ]; then
		_done='n'
		__loop_err='y'
	fi
	if [ -z "$_dns_servers" ]; then
		_done='n'
		__loop_err='y'
	fi
	echo
	if [ -z "$_done" ]; then
		_done='n'
	fi
	if [ "$_done" == 'N' ]; then
		_done='n'
	fi
done

if [ -z "$_netmask" ]; then
	_netmask=255.255.255.0
fi

echo "Fixing host's name..."
_hostname="$_namefix-zabbix-proxy"
echo $_hostname > /etc/hostname
cat /etc/hosts | sed -e "s/generic-zabbix-proxy/$_hostname/" > /tmp/zstmp
mv /tmp/zstmp /etc/hosts

echo "Fixing host's network configuration..."
cat /etc/network/interfaces | sed -e "s/192.168.66.165/$_lan_ip/" > /tmp/zstmp
mv /tmp/zstmp /etc/network/interfaces
cat /etc/network/interfaces | sed -e "s/255.255.255.0/$_netmask/" > /tmp/zstmp
mv /tmp/zstmp /etc/network/interfaces
cat /etc/network/interfaces | sed -e "s/192.168.66.1/$_gw_ip/" > /tmp/zstmp
mv /tmp/zstmp /etc/network/interfaces
cat /etc/network/interfaces | sed -e "s/192.168.66.2/$_dns_servers/" > /tmp/zstmp
mv /tmp/zstmp /etc/network/interfaces

echo "Fixing zabbix configuration..."
cat /opt/zabbix/etc/zabbix_proxy.conf | sed -e "s/generic-zabbix-proxy/$_hostname/" > /tmp/zstmp
mv /tmp/zstmp /opt/zabbix/etc/zabbix_proxy.conf
cat /opt/zabbix/etc/zabbix_agentd.conf | sed -e "s/generic-zabbix-proxy/$_hostname/" > /tmp/zstmp
mv /tmp/zstmp /opt/zabbix/etc/zabbix_agentd.conf

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

echo 'Done!'

echo
echo '### REMINDER ###'
echo
echo "Do not forget to enable ${__txt_bold}port forwarding${__txt_normal}."
echo "Forward port 10050 on the device at $_gw_ip to this machine ($_lan_ip)."
echo "For maintenance, additionally forward port 22022 to this machine's port 22."
echo
echo "Please ${__txt_bold}reboot the server now${__txt_normal} to apply all changes."
