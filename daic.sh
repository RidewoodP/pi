#!/bin/bash

# DAIC v1.0 (Paddee)
#Device
#And
#Info
#Collector

# collecting stats

echo "Host: " $(uname -n) " : " $(hostname -f)
echo "Host: " $(uname -a)
echo "Host: " $(cat /etc/oracle-release)
echo "Host: " $(uptime)

echo ; echo "LOGIN: Last logins"
last -n20 | sed 's/^/LOGIN: /'

echo ; echo "MEMORY: info"
grep Tot /proc/meminfo | column -t | sed 's/^/MEMORY: /'

echo ; echo "DMI: info"
dmidecode -t1 | sed 's/^/DMI: /'

echo ; echo "DISK_USAGE: File system usage"
df -hPl 2>/dev/null | column -t | sed 's/^/DISK_USAGE: /'

# Hardware only status collection
echo ; echo "DELL: Hardware check"
if [ -f /usr/sbin/omreport ] ; then
    echo ;  echo "DELL: Hardware check - Physical Disk Status"
    /usr/sbin/omreport storage pdisk controller=0|egrep "^ID |Status|State|Failure" | sed 's/^/DELL: /'
    
    echo ;  echo "DELL: Hardware check - Logical  Disk Status"
    /usr/sbin/omreport storage vdisk|egrep "^Name|State|Write|Read"                 | sed 's/^/DELL: /'
    
    echo ;  echo "DELL: Hardware check - Controler Status"
    /usr/sbin/omreport storage controller|egrep "^ID|^State|^Status|^Firmware"      | sed 's/^/DELL: /'
    
    
    echo ;  echo "DELL: Hardware check - System Memory Status"
    /usr/sbin/omreport chassis memory | egrep -A4 "Index.*[0-9]"                    | sed 's/^/DELL: /'
    
    echo ;  echo "DELL: Hardware check - System temps"
    /usr/sbin/omreport chassis temps | egrep -A3 "Index.*[0-9]"                     | sed 's/^/DELL: /'
    
    
    #echo ; echo ; echo "DELL: Hardware check  - HW Summary "
    #/usr/sbin/omreport system summary                                               | sed 's/^/DELL: /'
    echo
else
    echo "DELL: Hardware application not installed/applicable"                      | sed 's/^/DELL: /'
fi

echo ; echo IP_INFO: Information
for II in $(ls -1 /sys/class/net/ | egrep -wv "lo|bonding_masters" ) ; do
    ip a show $II 2>/dev/null
done | sed 's/^/IP_INFO: /'

echo ; echo ROUTING: Route Table
ip route show  | column -t | sed 's/^/ROUTING: /'

echo ; echo "USERS: (ID>99)"
getent passwd | awk -F : '{if ($3>99){print $0}}' | sed 's/^/USERS: /'

echo ; echo "SUDO info, who can do what"
egrep -v "^(#|$)" /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v :Default | column -t | sed 's/^/SUDO: /'

for GG in $(grep -h ^% /etc/sudoers /etc/sudoers.d/* 2>/dev/null | sed 's/^\%\([^[:space:]]*\)[[:space:]]*.*/\1/')
do  getent group $GG
done | sed 's/^/SUDO: GROUPS: /'

echo ; echo "NTP: conf (peers and servers only)"
egrep "^(peer|server)" /etc/ntp.conf | sed 's/^/NTP: /'

echo ; echo SECURITY: various setting
openssl ciphers -v | awk '{print $2}' | sort -u | sed 's/^/SECURITY: SSL: /'
echo
firewall-cmd --list-all 2>/dev/null | sed 's/^/SECURITY: FIREWALLD: /'
echo
iptables -nvL 2>/dev/null | sed 's/^/SECURITY: IPTABLES: /'

echo ; echo SERVICES: listening ports
ss -ntlp | sed 's/^/SERVICES: /' | column -t
echo


echo ; echo RPM:
echo "RPM: Name;Version;Install date;Vendor;Build"
rpm -qa --queryformat "RPM: %{name};%{version}-%{release}-%{ARCH};%{installtime:date};%{vendor};%{buildhost}\n" 2>/dev/null | sort -k2 -t\

echo ; echo "ERROR: Error messages"
egrep -i "fail|error|warn" /var/log/messages /var/log/boot.log /var/log/secure /var/log/kernel 2>/dev/null | sed 's/^/ERROR: /'

echo ; echo "Date collected "`date`


