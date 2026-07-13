#!/bin/bash

# Output HTML file
OUTPUT_FILE="/opt/monitoring/www/html/index.html"

# Upstream DNS servers to test
DNS_UPSTREAMS="208.67.222.222 1.1.1.1 9.9.9.9"

append_throttle_message() {
  local target_var="$1"
  local mask="$2"
  local text="$3"

  if (( THROTTLE_DEC & mask )); then
    printf -v "$target_var" '%s%s\n' "${!target_var}" "$text"
  fi
}

check_dns() {
  local server="$1"
  local udp_status="FAIL"
  local tcp_status="FAIL"

  if command -v dig >/dev/null 2>&1; then
    # Query a stable public domain to validate recursive resolution.
    if dig @"$server" cloudflare.com +short +time=2 +tries=1 >/dev/null 2>&1; then
      udp_status="OK"
    fi
    if dig +tcp @"$server" cloudflare.com +short +time=3 +tries=1 >/dev/null 2>&1; then
      tcp_status="OK"
    fi
  else
    udp_status="N/A (dig missing)"
    tcp_status="N/A (dig missing)"
  fi

  echo "$server|$udp_status|$tcp_status"
}

# Collect system information
HOSTNAME=$(hostname)
UPTIME=$(uptime -p)
CPU_LOAD=$(uptime | sed 's/.*load average: //')
MEMORY_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
PI_TEMP=$(vcgencmd measure_temp | cut -d'=' -f2 | cut -d"'" -f1)
PI_VOLT=$(vcgencmd measure_volts core | cut -d'=' -f2 | cut -d'V' -f1)
NETWORK_INTERFACES=$(ip -o -4 addr show | awk '$2 == "wlan0" || $2 == "eth0" {print $2 " " $4}')
THROTTLE_RAW=$(vcgencmd get_throttled 2>/dev/null)
THROTTLE_HEX=$(echo "$THROTTLE_RAW" | sed -n 's/.*throttled=\(0x[0-9a-fA-F]*\).*/\1/p')

if [ -n "$THROTTLE_HEX" ]; then
  THROTTLE_DEC=$((THROTTLE_HEX))
else
  THROTTLE_DEC=0
  THROTTLE_HEX="0x0"
fi

THROTTLE_CURRENT=""
THROTTLE_HISTORY=""
append_throttle_message THROTTLE_CURRENT $((1 << 0)) "Under-voltage detected now"
append_throttle_message THROTTLE_CURRENT $((1 << 1)) "Arm frequency capped now"
append_throttle_message THROTTLE_CURRENT $((1 << 2)) "Currently throttled"
append_throttle_message THROTTLE_CURRENT $((1 << 3)) "Soft temperature limit active now"
append_throttle_message THROTTLE_HISTORY $((1 << 16)) "Under-voltage has occurred since boot"
append_throttle_message THROTTLE_HISTORY $((1 << 17)) "Arm frequency capping has occurred since boot"
append_throttle_message THROTTLE_HISTORY $((1 << 18)) "Throttling has occurred since boot"
append_throttle_message THROTTLE_HISTORY $((1 << 19)) "Soft temperature limit has occurred since boot"

THROTTLE_SUMMARY="No throttling detected"
if [ -n "$THROTTLE_CURRENT" ]; then
  THROTTLE_SUMMARY="Active throttling or power issue"
elif [ -n "$THROTTLE_HISTORY" ]; then
  THROTTLE_SUMMARY="No active issue, but historical events recorded"
fi

# Start HTML content
echo "<html>
<head>
<title>System Monitoring Report</title>
<meta charset='utf-8'>
<meta http-equiv='refresh' content='30'>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  h2 { color: #333; }
  h3 { color: #333; margin-top: 28px; }
  table { width: 100%; border-collapse: collapse; margin-top: 20px; }
  th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
  th { background-color: #f4f4f4; }
  .ok { color: #176d2f; font-weight: 600; }
  .fail { color: #aa1e1e; font-weight: 600; }
  .na { color: #555; font-weight: 600; }
</style>
</head>
<body>
<h2>System Monitoring Report</h2>
<p><strong>Hostname:</strong> $HOSTNAME</p>
<p><strong>Uptime:</strong> $UPTIME</p>
<p><strong>CPU Throttling Status:</strong> $THROTTLE_SUMMARY</p>
<ul>" > "$OUTPUT_FILE"

echo "<li>Raw status: $THROTTLE_HEX</li>" >> "$OUTPUT_FILE"

if [ -n "$THROTTLE_CURRENT" ]; then
  echo "<li>Active flags:<ul>" >> "$OUTPUT_FILE"
  while IFS= read -r throttle_msg; do
    [ -n "$throttle_msg" ] && echo "<li>$throttle_msg</li>"
  done <<EOF >> "$OUTPUT_FILE"
$THROTTLE_CURRENT
EOF
  echo "</ul></li>" >> "$OUTPUT_FILE"
else
  echo "<li>Active flags: none</li>" >> "$OUTPUT_FILE"
fi

if [ -n "$THROTTLE_HISTORY" ]; then
  echo "<li>Historical flags:<ul>" >> "$OUTPUT_FILE"
  while IFS= read -r throttle_msg; do
    [ -n "$throttle_msg" ] && echo "<li>$throttle_msg</li>"
  done <<EOF >> "$OUTPUT_FILE"
$THROTTLE_HISTORY
EOF
  echo "</ul></li>" >> "$OUTPUT_FILE"
else
  echo "<li>Historical flags: none</li>" >> "$OUTPUT_FILE"
fi

echo "</ul>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>CPU Load (1, 5, 15 min)</td><td>$CPU_LOAD</td></tr>
<tr><td>Memory Usage</td><td>$MEMORY_USAGE</td></tr>
<tr><td>Disk Usage (Root Partition)</td><td>$DISK_USAGE</td></tr>
<tr><td>Temperature</td><td>$PI_TEMP &deg;C</td></tr>
<tr><td>Core Voltage</td><td>$PI_VOLT V</td></tr>
<tr><td>Network Interfaces</td><td><ul>" >> "$OUTPUT_FILE"

# Add network interfaces to the HTML file
while IFS= read -r iface; do
  [ -n "$iface" ] && echo "<li>$iface</li>"
done <<EOF >> "$OUTPUT_FILE"
$NETWORK_INTERFACES
EOF

echo "</ul></td></tr>
</table>
<h3>DNS Upstream Health</h3>
<table>
<tr><th>Upstream</th><th>UDP 53</th><th>TCP 53</th></tr>" >> "$OUTPUT_FILE"

for server in $DNS_UPSTREAMS; do
  result=$(check_dns "$server")
  upstream=$(echo "$result" | awk -F'|' '{print $1}')
  udp=$(echo "$result" | awk -F'|' '{print $2}')
  tcp=$(echo "$result" | awk -F'|' '{print $3}')

  udp_class="fail"
  tcp_class="fail"

  if [[ "$udp" == "OK" ]]; then
    udp_class="ok"
  elif [[ "$udp" == N/A* ]]; then
    udp_class="na"
  fi

  if [[ "$tcp" == "OK" ]]; then
    tcp_class="ok"
  elif [[ "$tcp" == N/A* ]]; then
    tcp_class="na"
  fi

  echo "<tr><td>$upstream</td><td class='$udp_class'>$udp</td><td class='$tcp_class'>$tcp</td></tr>" >> "$OUTPUT_FILE"
done

echo "</table>
<p>Report generated on: $(date)</p>
</body>
</html>" >> "$OUTPUT_FILE"

# Set correct permissions
chmod 644 "$OUTPUT_FILE"

# Display message
#echo "System report generated at $OUTPUT_FILE"
