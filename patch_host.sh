#!/bin/bash
# This script is used to patch the host system for the pi user. It should be run as root.

# set our path to include sbin directories
export PATH="${PATH}:/usr/sbin:/sbin"
REBOOT_REQUIRED=false

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Update the package list and upgrade the system
apt update && apt upgrade -y

# check if reboot is required
if [ -f /var/run/reboot-required ]; then
  echo "Reboot is required. Rebooting now..."
  REBOOT_REQUIRED=true
  exit
fi

# further reboot check
# if 'needrestart' is installed, check if a reboot is required
if command -v needrestart >/dev/null 2>&1; then
  KRN_RESTART=$(needrestart -b 2>/dev/null | grep UCEXP | sed 's/.*: //') # list of kernel modules to restart
  if [ -n "$KRN_RESTART" ]; then
    echo "Restart required for kernel"
    REBOOT_REQUIRED=true
  fi
  
  SVR_RESTART=$(needrestart -b 2>/dev/null | grep SVC   | sed 's/.*: //') # list of services to restart

  if [ -n "${SVR_RESTART}" ]; then
    echo "Restarting services"
    for SS in ${SVR_RESTART}; do
      echo "systemctl restart ${SS}"
      # systemctl restart "${SS}"
    done
  fi
fi