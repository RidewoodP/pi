#!/bin/bash

# DAIC v1.0 (Paddee)
#Device
#And
#Info
#Collector

# collecting stats

echo "================================================================================"
echo "HOST INFORMATION"
echo "================================================================================"
printf "  Hostname (short):  %s\n" "$(uname -n)"
printf "  Hostname (FQDN):   %s\n" "$(hostname -f)"
printf "  System:            %s\n" "$(uname -s)"
grep PRETTY_NAME /etc/os-release | sed 's/^/  OS:                /; s/PRETTY_NAME=//; s/"//g'
printf "  Uptime:            %s\n" "$(uptime | sed 's/^[^,]*up *//')"
echo

echo "================================================================================"
echo "LOGIN: Last 20 logins"
echo "================================================================================"
last -n20 | sed 's/^/  /'
echo

echo "================================================================================"
echo "MEMORY: System Memory Info"
echo "================================================================================"
grep Tot /proc/meminfo | awk '{printf "  %-30s %15s\n", $1, $2" KB"}' | sed 's/Total/Total Memory/'
echo

echo ; echo "DMI: info"
dmidecode -t1 | sed 's/^/DMI: /'

echo "================================================================================"
echo "DISK USAGE: File System Utilization"
echo "================================================================================"
df -hPl 2>/dev/null | awk 'NR==1 {printf "%-20s %10s %10s %10s %8s  %s\n", "Filesystem", "Size", "Used", "Available", "Use%", "Mounted on"} NR>1 {printf "%-20s %10s %10s %10s %8s  %s\n", $1, $2, $3, $4, $5, $6}'
echo

# Hardware only status collection
echo "================================================================================"
echo "DELL: Hardware Status"
echo "================================================================================"
if [ -f /usr/sbin/omreport ] ; then
    echo "  Physical Disk Status:"
    /usr/sbin/omreport storage pdisk controller=0 2>/dev/null | grep -E "^ID |Status|State|Failure" | sed 's/^/    /'
    
    echo "  Logical Disk Status:"
    /usr/sbin/omreport storage vdisk 2>/dev/null | grep -E "^Name|State|Write|Read" | sed 's/^/    /'
    
    echo "  Controller Status:"
    /usr/sbin/omreport storage controller 2>/dev/null | grep -E "^ID|^State|^Status|^Firmware" | sed 's/^/    /'
    
    echo "  System Memory Status:"
    /usr/sbin/omreport chassis memory 2>/dev/null | grep -E -A4 "Index.*[0-9]" | sed 's/^/    /'
    
    echo "  System Temperatures:"
    /usr/sbin/omreport chassis temps 2>/dev/null | grep -E -A3 "Index.*[0-9]" | sed 's/^/    /'
else
    echo "  DELL OpenManage not installed or not applicable"
fi
echo

echo "================================================================================"
echo "NETWORK INTERFACES"
echo "================================================================================"
for II in /sys/class/net/*; do
    [[ "$II" =~ (lo|bonding_masters) ]] && continue
    ip a show "$(basename "$II")" 2>/dev/null | sed 's/^/  /'
done
echo

echo "================================================================================"
echo "ROUTING: Route Table"
echo "================================================================================"
ip route show 2>/dev/null | awk 'NR==1 {printf "%-40s %-15s %-10s\n", "Destination", "Gateway", "Interface"} {printf "%-40s %-15s %-10s\n", $1, $3, $5}' | head -20
echo

echo "================================================================================"
echo "USERS: System Users (UID > 99)"
echo "================================================================================"
getent passwd | awk -F : '{if ($3>99){printf "%-25s %-8s %-8s  %s\n", $1, "UID:"$3, "GID:"$4, $7}}' | sed 's/^/  /'
echo

echo "================================================================================"
echo "SUDO: Sudoers Configuration"
echo "================================================================================"
{
    echo "  Sudoers Rules:"
    grep -E -v "^(#|$)" /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v :Default | sed 's/^/    /'
    echo
    echo "  Sudoers Groups:"
    for GG in $(grep -h ^% /etc/sudoers /etc/sudoers.d/* 2>/dev/null | sed 's/^\%\([^[:space:]]*\)[[:space:]]*.*/\1/')
    do 
        getent group "${GG}" | sed 's/^/    /'
    done
} | head -50
echo

echo ; echo "NTP: conf (peers and servers only)"
if [ -f /etc/ntp.conf ]; then
    grep -E "^(peer|server)" /etc/ntp.conf | sed 's/^/NTP: /'
elif [ -f /etc/chrony.conf ]; then
    grep -E "^(peer|server)" /etc/chrony.conf | sed 's/^/NTP: /'
else
    echo "NTP: No NTP/Chrony configuration found" | sed 's/^/NTP: /'
fi

echo "================================================================================"
echo "SECURITY: Configuration & Settings"
echo "================================================================================"
echo "  SSL/TLS Ciphers (unique):"
openssl ciphers -v 2>/dev/null | awk '{print $2}' | sort -u | sed 's/^/    /' | head -20
echo
echo "  Firewall Status (firewalld):"
firewall-cmd --list-all 2>/dev/null | sed 's/^/    /' | head -30 || echo "    firewalld not available"
echo
echo "  IPTables Rules (sample):"
iptables -nvL 2>/dev/null | sed 's/^/    /' | head -30 || echo "    iptables not available"
echo

echo "================================================================================"
echo "SERVICES: Listening Ports"
echo "================================================================================"
ss -ntlp 2>/dev/null | awk 'NR==1 {printf "%-10s %-30s %-50s\n", "Proto", "Local Address", "Process"} NR>1 {printf "%-10s %-30s %-50s\n", $1, $4, $7}' | sed 's/^/  /'
echo


echo
echo "================================================================================"
echo "PACKAGES: Installed"
echo "================================================================================"
if command -v rpm >/dev/null 2>&1 ; then
    {
        printf "  %-50s %-25s %-12s %-25s %s\n" "Name" "Version" "Date" "Vendor" "Build Host"
        printf "  %-50s %-25s %-12s %-25s %s\n" "---" "---" "---" "---" "---"
        rpm -qa --queryformat "%{name};%{version}-%{release}-%{ARCH};%{installtime:date};%{vendor};%{buildhost}\n" 2>/dev/null | \
        LC_ALL=C sort -t";" -k1,1 | awk -F";" '{printf "  %-50s %-25s %-12s %-25s %s\n", $1, $2, $3, $4, $5}' | head -50
    }
elif command -v dpkg >/dev/null 2>&1 ; then
    {
        printf "  %-50s %-25s\n" "Name" "Version"
        printf "  %-50s %-25s\n" "---" "---"
        dpkg-query -W -f='${Package};${Version}\n' 2>/dev/null | \
        LC_ALL=C sort -t";" -k1,1 | awk -F";" '{printf "  %-50s %-25s\n", $1, $2}' | head -50
    }
else
    echo "  Package manager not found"
fi
echo

echo "================================================================================"
echo "ERROR LOGS: Recent Errors & Warnings"
echo "================================================================================"
TODAY="$(date '+%b %e')"
echo "  Syslog Errors from Today:"
journalctl --since today -p 3 -q | sed 's/^/    /' || echo "    No recent errors found"
echo
echo "  Boot Log Errors & Warnings from Yesterday:"
journalctl --since yesterday -k -p6 --case-sensitive=0 -g "fail|error|warn" | sed 's/^/    /'
echo
echo "================================================================================"
printf "Report generated: %s\n" "$(date)"
echo "================================================================================"
