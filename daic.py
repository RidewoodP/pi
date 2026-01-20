#!/usr/bin/env python3
"""Python port of daic.sh (device and info collector)."""

import argparse
import datetime
import os
import platform
import shutil
import socket
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description="DAIC system collector")
parser.add_argument(
    "--collect-packages",
    choices=["0", "1"],
    help="Set to 1 to collect packages, 0 to skip (overrides COLLECT_PACKAGES env)",
)
parser.set_defaults(collect_packages=None)
args = parser.parse_args()

env_collect = os.getenv("COLLECT_PACKAGES")
env_collect_bool = env_collect.lower() == "true" if env_collect else None
arg_collect_bool = None
if args.collect_packages is not None:
    arg_collect_bool = args.collect_packages == "1"

COLLECT_PACKAGES = (
    arg_collect_bool
    if arg_collect_bool is not None
    else (env_collect_bool if env_collect_bool is not None else False)
)

SEP = "=" * 80
NDATE = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def run_cmd(cmd: str) -> tuple[int, str]:
    """Run a shell command and return (returncode, stdout)."""
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    out = proc.stdout.strip()
    if proc.stderr and not out:
        out = proc.stderr.strip()
    return proc.returncode, out


def print_block(title: str, body: str) -> None:
    print(SEP)
    print(title)
    print(SEP)
    if body:
        print(body)
    else:
        print("  (no data)")


def indent_lines(text: str, prefix: str = "  ") -> str:
    return "\n".join(f"{prefix}{line}" for line in text.splitlines())


# Host information
host_short = socket.gethostname()
host_fqdn = socket.getfqdn()
os_pretty = "unknown"
for line in Path("/etc/os-release").read_text().splitlines():
    if line.startswith("PRETTY_NAME="):
        os_pretty = line.split("=", 1)[1].strip('"')
        break
system_name = platform.system()

rc, uptime_raw = run_cmd("uptime")
uptime_clean = uptime_raw
if " up " in uptime_raw:
    uptime_clean = uptime_raw.split(" up ", 1)[1]
    if "," in uptime_clean:
        uptime_clean = uptime_clean.split(",", 1)[0].strip()

host_body = "\n".join(
    [
        f"  Hostname (short):  {host_short}",
        f"  Hostname (FQDN):   {host_fqdn}",
        f"  System:            {system_name}",
        f"  OS:                {os_pretty}",
        f"  Uptime:            {uptime_clean}",
    ]
)
print_block("HOST INFORMATION", host_body)

# Login history
rc, last_out = run_cmd("last -n20")
login_body = indent_lines(last_out) if rc == 0 else "  last command not available"
print_block("LOGIN: Last 20 logins", login_body)

# Memory info
mem_lines = []
try:
    for line in Path("/proc/meminfo").read_text().splitlines():
        if "Tot" in line:
            parts = line.split()
            if len(parts) >= 2:
                mem_lines.append(f"  {parts[0]:<30} {parts[1]} KB")
except FileNotFoundError:
    mem_lines.append("  /proc/meminfo not available")
print_block("MEMORY: System Memory Info", "\n".join(mem_lines))

# DMI info
rc, dmi_out = run_cmd("dmidecode -t1")
dmi_body = indent_lines(dmi_out.replace("\n", "\nDMI: ")) if rc == 0 else "  dmidecode not available"
print_block("DMI: info", dmi_body)

# Disk usage
rc, df_out = run_cmd('df -hPl 2>/dev/null | awk "NR==1 {printf \"%-20s %10s %10s %10s %8s  %s\\n\", \"Filesystem\", \"Size\", \"Used\", \"Available\", \"Use%\", \"Mounted on\"} NR>1 {printf \"%-20s %10s %10s %10s %8s  %s\\n\", $1, $2, $3, $4, $5, $6}"')
df_body = df_out if rc == 0 else "  df not available"
print_block("DISK USAGE: File System Utilization", df_body)

# Dell hardware status
if shutil.which("omreport") or Path("/usr/sbin/omreport").exists():
    sections = []
    commands = {
        "  Physical Disk Status:": "/usr/sbin/omreport storage pdisk controller=0 2>/dev/null | grep -E '^ID |Status|State|Failure'",
        "  Logical Disk Status:": "/usr/sbin/omreport storage vdisk 2>/dev/null | grep -E '^Name|State|Write|Read'",
        "  Controller Status:": "/usr/sbin/omreport storage controller 2>/dev/null | grep -E '^ID|^State|^Status|^Firmware'",
        "  System Memory Status:": "/usr/sbin/omreport chassis memory 2>/dev/null | grep -E -A4 'Index.*[0-9]'",
        "  System Temperatures:": "/usr/sbin/omreport chassis temps 2>/dev/null | grep -E -A3 'Index.*[0-9]'",
    }
    for title, cmd in commands.items():
        rc, out = run_cmd(cmd)
        body = indent_lines(out, prefix="    ") if out else "    (no data)"
        sections.append(f"{title}\n{body}")
    dell_body = "\n\n".join(sections)
else:
    dell_body = "  DELL OpenManage not installed or not applicable"
print_block("DELL: Hardware Status", dell_body)

# Network interfaces
net_sections = []
net_dir = Path("/sys/class/net")
if net_dir.exists():
    for iface in sorted(net_dir.iterdir()):
        name = iface.name
        if name in {"lo", "bonding_masters"}:
            continue
        rc, out = run_cmd(f"ip a show {name} 2>/dev/null")
        if out:
            net_sections.append(indent_lines(out))
net_body = "\n".join(net_sections) if net_sections else "  No interfaces found"
print_block("NETWORK INTERFACES", net_body)

# Routing
rc, route_out = run_cmd("ip route show 2>/dev/null | awk 'NR==1 {printf \"%-40s %-15s %-10s\\n\", \"Destination\", \"Gateway\", \"Interface\"} {printf \"%-40s %-15s %-10s\\n\", $1, $3, $5}' | head -20")
route_body = route_out if rc == 0 else "  ip route not available"
print_block("ROUTING: Route Table", route_body)

# Users
rc, passwd_out = run_cmd("getent passwd")
user_lines = []
if rc == 0:
    for line in passwd_out.splitlines():
        parts = line.split(":")
        if len(parts) >= 7:
            uid = int(parts[2])
            if uid > 99:
                user_lines.append(f"  {parts[0]:<25} UID:{parts[2]:<8} GID:{parts[3]:<8}  {parts[6]}")
else:
    user_lines.append("  getent not available")
print_block("USERS: System Users (UID > 99)", "\n".join(user_lines))

# Sudoers
sudo_sections = ["  Sudoers Rules:"]
rc, sudo_rules = run_cmd("grep -E -v '^(#|$)' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v :Default")
if sudo_rules:
    sudo_sections.append(indent_lines(sudo_rules, prefix="    "))
else:
    sudo_sections.append("    (no sudoers entries)")
sudo_sections.append("\n  Sudoers Groups:")
rc, sudo_groups = run_cmd("grep -h ^% /etc/sudoers /etc/sudoers.d/* 2>/dev/null | sed 's/^%\\([^[:space:]]*\\)[[:space:]].*/\\1/'")
if sudo_groups:
    for gg in sudo_groups.split():
        rc, gline = run_cmd(f"getent group {gg}")
        if gline:
            sudo_sections.append(f"    {gline}")
sudo_body = "\n".join(sudo_sections)
print_block("SUDO: Sudoers Configuration", sudo_body)

# NTP
ntp_body = ""
ntp_conf = Path("/etc/ntp.conf")
chrony_conf = Path("/etc/chrony.conf")
if ntp_conf.exists():
    rc, out = run_cmd("grep -E '^(peer|server)' /etc/ntp.conf")
    ntp_body = out.replace("\n", "\nNTP: ") if out else "NTP: (no peer/server entries)"
elif chrony_conf.exists():
    rc, out = run_cmd("grep -E '^(peer|server)' /etc/chrony.conf")
    ntp_body = out.replace("\n", "\nNTP: ") if out else "NTP: (no peer/server entries)"
else:
    ntp_body = "NTP: No NTP/Chrony configuration found"
print(f"\n{ntp_body}")

# Security
rc, ciphers_out = run_cmd("openssl ciphers -v 2>/dev/null")
ciphers = []
if ciphers_out:
    for line in ciphers_out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            ciphers.append(parts[1])
    ciphers = sorted(set(ciphers))[:20]
sec_lines = ["  SSL/TLS Ciphers (unique):"] + [f"    {c}" for c in ciphers]
rc, fw_out = run_cmd("firewall-cmd --list-all 2>/dev/null | head -30")
sec_lines.append("  Firewall Status (firewalld):")
sec_lines.append(indent_lines(fw_out, prefix="    ") if fw_out else "    firewalld not available")
rc, ipt_out = run_cmd("iptables -nvL 2>/dev/null | head -30")
sec_lines.append("  IPTables Rules (sample):")
sec_lines.append(indent_lines(ipt_out, prefix="    ") if ipt_out else "    iptables not available")
print_block("SECURITY: Configuration & Settings", "\n".join(sec_lines))

# Services listening
rc, ss_out = run_cmd("ss -ntlp 2>/dev/null | awk 'NR==1 {printf \"%-10s %-30s %-50s\\n\", \"Proto\", \"Local Address\", \"Process\"} NR>1 {printf \"%-10s %-30s %-50s\\n\", $1, $4, $7}'")
ss_body = indent_lines(ss_out) if ss_out else "  ss not available"
print_block("SERVICES: Listening Ports", ss_body)

# Packages (optional)
print(f"\n{SEP}")
print("PACKAGES: Installed")
print(SEP)
if COLLECT_PACKAGES:
    if shutil.which("rpm"):
        rc, out = run_cmd("rpm -qa --queryformat '%{name};%{version}-%{release}-%{ARCH};%{installtime:date};%{vendor};%{buildhost}\n' 2>/dev/null | LC_ALL=C sort -t';' -k1,1 | awk -F';' '{printf \"  %-50s %-25s %-12s %-25s %s\\n\", $1, $2, $3, $4, $5}' | head -50")
        print(out or "  (no rpm data)")
    elif shutil.which("dpkg-query"):
        rc, out = run_cmd("dpkg-query -W -f='${Package};${Version}\n' 2>/dev/null | LC_ALL=C sort -t';' -k1,1 | awk -F';' '{printf \"  %-50s %-25s\\n\", $1, $2}' | head -50")
        print(out or "  (no dpkg data)")
    else:
        print("  Package manager not found")
else:
    print("  Package collection skipped (COLLECT_PACKAGES=false)")

# Error logs
print(SEP)
print("ERROR LOGS: Recent Errors & Warnings")
print(SEP)
rc, syslog_out = run_cmd("journalctl --since today -p 3 -q")
print("  Syslog Errors from Today:")
print(indent_lines(syslog_out, prefix="    ") if syslog_out else "    No recent errors found")
print()
rc, boot_out = run_cmd("journalctl --since yesterday -k -p6 --case-sensitive=0 -g 'fail|error|warn'")
print("  Boot Log Errors & Warnings from Yesterday:")
print(indent_lines(boot_out, prefix="    ") if boot_out else "    No recent boot errors found")

print(SEP)
print(f"Report generated: {NDATE}")
print(SEP)
