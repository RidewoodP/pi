# pi

## Summary of Scripts

### daic.sh

`daic.sh` stands for Device And Info Collector. This script is designed to gather extensive system information and perform hardware checks. Below is an overview of its functionality:

- **Host Information**: Displays host name, kernel version, and system uptime.
- **Login History**: Shows the last 20 login attempts.
- **Memory Details**: Lists memory statistics from `/proc/meminfo`.
- **DMI Information**: Uses `dmidecode` to extract system information.
- **Disk Usage**: Displays file system usage with `df`.
- **Hardware Checks (Dell Systems)**: 
  - Physical and logical disk statuses.
  - Controller status and firmware details.
  - System memory status.
  - Temperature readings.
- **Network Information**: 
  - Details of all active network interfaces (excluding `lo` and bonding masters).
  - Routing table.
- **User Details**: Displays user accounts with IDs greater than 99.
- **Sudoers Information**: Lists sudo privileges and groups.
- **NTP Configuration**: Lists NTP peers and servers from `/etc/ntp.conf`.
- **Security Settings**: 
  - Lists supported SSL ciphers.
  - Displays firewall rules (`firewalld` and `iptables`).
- **Services**: Lists all listening ports.
- **Installed Software**: Summarizes installed RPM packages.
- **Error Logs**: Extracts errors, warnings, and failures from system logs.

This script is highly useful for system administrators and engineers who need a quick snapshot of a system's state.