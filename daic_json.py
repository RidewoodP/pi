#!/usr/bin/env python3
"""Python DAIC collector with JSON output."""

import argparse
import datetime
import json
import os
import platform
import shlex
import shutil
import socket
import subprocess
from pathlib import Path


def parse_bool(value: str | bool) -> bool:
    """Parse common boolean string values."""
    if isinstance(value, bool):
        return value

    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    raise argparse.ArgumentTypeError(
        "Expected one of: 1, 0, true, false, yes, no, on, off"
    )


parser = argparse.ArgumentParser(description="DAIC system collector")
collect_group = parser.add_mutually_exclusive_group()
collect_group.add_argument(
    "-c",
    "--collect-packages",
    nargs="?",
    const=True,
    type=parse_bool,
    metavar="{0,1,true,false}",
    help=(
        "Enable package collection. Optional value accepts 1/0, true/false, yes/no "
        "(overrides COLLECT_PACKAGES env)."
    ),
)
collect_group.add_argument(
    "--no-collect-packages",
    action="store_false",
    dest="collect_packages",
    help="Disable package collection (overrides COLLECT_PACKAGES env).",
)
parser.set_defaults(collect_packages=None)
args = parser.parse_args()

env_collect = os.getenv("COLLECT_PACKAGES")
env_collect_bool = None
if env_collect is not None:
    try:
        env_collect_bool = parse_bool(env_collect)
    except argparse.ArgumentTypeError as exc:
        parser.error(f"Invalid COLLECT_PACKAGES value '{env_collect}': {exc}")

COLLECT_PACKAGES = (
    args.collect_packages
    if args.collect_packages is not None
    else (env_collect_bool if env_collect_bool is not None else False)
)

NDATE = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def run_cmd(cmd: str) -> dict:
    """Run a shell command and return return code, stdout, and stderr."""
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return {
        "command": cmd,
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }


def safe_read_text(path: str) -> str:
    """Read file content safely and return empty string when unavailable."""
    try:
        return Path(path).read_text()
    except (FileNotFoundError, PermissionError, OSError):
        return ""


def parse_table_lines(raw: str) -> list[dict]:
    """Parse space-delimited tabular command output where first line is header."""
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    if len(lines) < 2:
        return []
    headers = lines[0].split()
    rows = []
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < len(headers):
            continue
        row = {headers[i]: parts[i] for i in range(len(headers) - 1)}
        row[headers[-1]] = " ".join(parts[len(headers) - 1 :])
        rows.append(row)
    return rows


def load_os_pretty_name() -> str:
    """Return PRETTY_NAME from /etc/os-release when present."""
    content = safe_read_text("/etc/os-release")
    for line in content.splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip('"')
    return "unknown"


def split_nonempty_lines(text: str) -> list[str]:
    return [line for line in text.splitlines() if line.strip()]


# Host information
host_short = socket.gethostname()
host_fqdn = socket.getfqdn()
os_pretty = load_os_pretty_name()
system_name = platform.system()

uptime_result = run_cmd("uptime")
uptime_raw = uptime_result["stdout"] or uptime_result["stderr"]
uptime_clean = uptime_raw or "unknown"
if " up " in uptime_clean:
    uptime_clean = uptime_clean.split(" up ", 1)[1]
    if "," in uptime_clean:
        uptime_clean = uptime_clean.split(",", 1)[0].strip()

report = {
    "generated_at": NDATE,
    "collect_packages": COLLECT_PACKAGES,
    "host_information": {
        "hostname_short": host_short,
        "hostname_fqdn": host_fqdn,
        "system": system_name,
        "os": os_pretty,
        "uptime": uptime_clean,
        "uptime_command": uptime_result,
    },
}

# Login history
last_result = run_cmd("last -n20")
report["login_history"] = {
    "entries": split_nonempty_lines(last_result["stdout"]),
    "command_result": last_result,
}

# Memory info
memory_totals = {}
mem_content = safe_read_text("/proc/meminfo")
for line in mem_content.splitlines():
    if "Tot" in line:
        parts = line.split()
        if len(parts) >= 2:
            key = parts[0].rstrip(":")
            value = int(parts[1]) if parts[1].isdigit() else parts[1]
            memory_totals[key] = value
report["memory"] = {
    "totals_kb": memory_totals,
    "source_file": "/proc/meminfo",
    "available": bool(mem_content),
}

# DMI info
dmi_result = run_cmd("dmidecode -t1")
report["dmi"] = {
    "lines": split_nonempty_lines(dmi_result["stdout"]),
    "command_result": dmi_result,
}

# Disk usage
df_result = run_cmd("df -hPl")
report["disk_usage"] = {
    "table": parse_table_lines(df_result["stdout"]),
    "command_result": df_result,
}

# Dell hardware status
if shutil.which("omreport") or Path("/usr/sbin/omreport").exists():
    dell_sections = {}
    commands = {
        "physical_disk_status": "/usr/sbin/omreport storage pdisk controller=0",
        "logical_disk_status": "/usr/sbin/omreport storage vdisk",
        "controller_status": "/usr/sbin/omreport storage controller",
        "system_memory_status": "/usr/sbin/omreport chassis memory",
        "system_temperatures": "/usr/sbin/omreport chassis temps",
    }
    for title, cmd in commands.items():
        result = run_cmd(cmd)
        dell_sections[title] = {
            "lines": split_nonempty_lines(result["stdout"]),
            "command_result": result,
        }
    report["dell_hardware"] = {
        "available": True,
        "sections": dell_sections,
    }
else:
    report["dell_hardware"] = {
        "available": False,
        "message": "DELL OpenManage not installed or not applicable",
    }

# Network interfaces
net_dir = Path("/sys/class/net")
network_interfaces = []
if net_dir.exists():
    for iface in sorted(net_dir.iterdir()):
        name = iface.name
        if name in {"lo", "bonding_masters"}:
            continue
        result = run_cmd(f"ip -j addr show {shlex.quote(name)}")
        parsed = None
        if result["stdout"]:
            try:
                parsed = json.loads(result["stdout"])
            except json.JSONDecodeError:
                parsed = None
        network_interfaces.append(
            {
                "name": name,
                "details": parsed,
                "raw": split_nonempty_lines(result["stdout"]),
                "command_result": result,
            }
        )
report["network_interfaces"] = network_interfaces

# Routing
route_result = run_cmd("ip -j route show")
route_data = []
if route_result["stdout"]:
    try:
        route_data = json.loads(route_result["stdout"])
    except json.JSONDecodeError:
        route_data = []
report["routing"] = {
    "routes": route_data,
    "raw": split_nonempty_lines(route_result["stdout"]),
    "command_result": route_result,
}

# Users
passwd_result = run_cmd("getent passwd")
passwd_lines = split_nonempty_lines(passwd_result["stdout"])
user_entries = []
if passwd_result["returncode"] == 0:
    for line in passwd_lines:
        parts = line.split(":")
        if len(parts) >= 7:
            uid = int(parts[2])
            if uid > 99:
                user_entries.append(
                    {
                        "user": parts[0],
                        "uid": uid,
                        "gid": int(parts[3]),
                        "home": parts[5],
                        "shell": parts[6],
                    }
                )
report["users"] = {
    "entries": user_entries,
    "raw_lines": passwd_lines,
    "command_result": {
        "command": passwd_result["command"],
        "returncode": passwd_result["returncode"],
        "stderr": passwd_result["stderr"],
    },
}

# Sudoers
sudo_rules_result = run_cmd(
    "grep -E -v '^(#|$)' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v :Default"
)
sudo_groups_result = run_cmd(
    "grep -h ^% /etc/sudoers /etc/sudoers.d/* 2>/dev/null | sed 's/^%\\([^[:space:]]*\\)[[:space:]].*/\\1/'"
)
sudo_group_details = []
for gg in split_nonempty_lines(sudo_groups_result["stdout"]):
    group_result = run_cmd(f"getent group {shlex.quote(gg)}")
    sudo_group_details.append(
        {
            "group": gg,
            "entry": group_result["stdout"],
            "command_result": group_result,
        }
    )
report["sudoers"] = {
    "rules": split_nonempty_lines(sudo_rules_result["stdout"]),
    "groups": sudo_group_details,
    "rules_command_result": sudo_rules_result,
    "groups_command_result": sudo_groups_result,
}

# NTP
ntp_conf = Path("/etc/ntp.conf")
chrony_conf = Path("/etc/chrony.conf")
ntp_source = "none"
ntp_result = {"command": "", "returncode": 1, "stdout": "", "stderr": ""}
if ntp_conf.exists():
    ntp_source = str(ntp_conf)
    ntp_result = run_cmd("grep -E '^(peer|server)' /etc/ntp.conf")
elif chrony_conf.exists():
    ntp_source = str(chrony_conf)
    ntp_result = run_cmd("grep -E '^(peer|server)' /etc/chrony.conf")
report["ntp"] = {
    "source": ntp_source,
    "peers": split_nonempty_lines(ntp_result["stdout"]),
    "command_result": ntp_result,
}

# Security
ciphers_result = run_cmd("openssl ciphers -v")
ciphers = []
if ciphers_result["stdout"]:
    for line in ciphers_result["stdout"].splitlines():
        parts = line.split()
        if len(parts) >= 2:
            ciphers.append(parts[1])
fw_result = run_cmd("firewall-cmd --list-all")
iptables_result = run_cmd("iptables -nvL")
report["security"] = {
    "ssl_tls_ciphers_unique": sorted(set(ciphers)),
    "ciphers_command_result": ciphers_result,
    "firewalld": {
        "lines": split_nonempty_lines(fw_result["stdout"]),
        "command_result": fw_result,
    },
    "iptables": {
        "lines": split_nonempty_lines(iptables_result["stdout"]),
        "command_result": iptables_result,
    },
}

# Services listening
ss_result = run_cmd("ss -ntlpH")
ss_lines = split_nonempty_lines(ss_result["stdout"])
listening_ports = []
for line in ss_lines:
    parts = line.split()
    if len(parts) >= 5:
        listening_ports.append(
            {
                "state": parts[0],
                "recv_q": parts[1],
                "send_q": parts[2],
                "local_address": parts[3],
                "peer_address": parts[4],
                "process": " ".join(parts[5:]) if len(parts) > 5 else "",
            }
        )
report["services_listening"] = {
    "entries": listening_ports,
    "raw_lines": ss_lines,
    "command_result": {
        "command": ss_result["command"],
        "returncode": ss_result["returncode"],
        "stderr": ss_result["stderr"],
    },
}

# Packages (optional)
if COLLECT_PACKAGES:
    if shutil.which("rpm"):
        packages_result = run_cmd(
            "rpm -qa --queryformat '%{name};%{version}-%{release}-%{ARCH};%{installtime:date};%{vendor};%{buildhost}\\n' | LC_ALL=C sort -t';' -k1,1"
        )
        packages = []
        for line in split_nonempty_lines(packages_result["stdout"]):
            parts = line.split(";")
            if len(parts) >= 5:
                packages.append(
                    {
                        "name": parts[0],
                        "version": parts[1],
                        "install_time": parts[2],
                        "vendor": parts[3],
                        "build_host": parts[4],
                    }
                )
        report["packages"] = {
            "enabled": True,
            "manager": "rpm",
            "items": packages,
            "command_result": {
                "command": packages_result["command"],
                "returncode": packages_result["returncode"],
                "stderr": packages_result["stderr"],
            },
        }
    elif shutil.which("dpkg-query"):
        packages_result = run_cmd(
            "dpkg-query -W -f='${Package};${Version}\\n' | LC_ALL=C sort -t';' -k1,1"
        )
        packages = []
        for line in split_nonempty_lines(packages_result["stdout"]):
            parts = line.split(";")
            if len(parts) >= 2:
                packages.append(
                    {
                        "name": parts[0],
                        "version": parts[1],
                    }
                )
        report["packages"] = {
            "enabled": True,
            "manager": "dpkg",
            "items": packages,
            "command_result": {
                "command": packages_result["command"],
                "returncode": packages_result["returncode"],
                "stderr": packages_result["stderr"],
            },
        }
    else:
        report["packages"] = {
            "enabled": True,
            "manager": "unknown",
            "items": [],
            "message": "Package manager not found",
        }
else:
    report["packages"] = {
        "enabled": False,
        "items": [],
        "message": "Package collection skipped (COLLECT_PACKAGES=false)",
    }

# Error logs
syslog_result = run_cmd("journalctl --since today -p 3 -q")
boot_result = run_cmd("journalctl --since yesterday -k -p6 --case-sensitive=0 -g 'fail|error|warn'")
report["error_logs"] = {
    "syslog_errors_today": split_nonempty_lines(syslog_result["stdout"]),
    "boot_logs_yesterday_warn_or_error": split_nonempty_lines(boot_result["stdout"]),
    "syslog_command_result": syslog_result,
    "boot_command_result": boot_result,
}

print(json.dumps(report, indent=2))
