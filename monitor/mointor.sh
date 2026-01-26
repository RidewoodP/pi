#!/bin/bash

# Output HTML file
OUTPUT_FILE="/opt/monitoring/www/html/index.html"

# Ensure target directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Collect system information
HOSTNAME=$(hostname)
UPTIME=$(uptime -p)
CPU_LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
MEMORY_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
NETWORK_INTERFACES=$(ip -o -4 addr show | awk '{print $2 " - " $4}')
THROTTLE=$(/usr/bin/vcgencmd get_throttled)
# Check for CPU throttling
#    Bit   Meaning
#   ----  ------------------------------------
#    0    Under-voltage detected
#    1    Arm frequency capped
#    2    Currently throttled
#    3    Soft temperature limit active
#   16    Under-voltage has occurred
#   17    Arm frequency capping has occurred
#   18    Throttling has occurred
#   19    Soft temperature limit has occurred

# Extract hex value and check each bit
THROTTLE_HEX=$(echo "$THROTTLE" | sed -n 's/.*throttled=\(0x[0-9a-fA-F]*\).*/\1/p')
THROTTLE_DEC=$((THROTTLE_HEX))

THROTTLE_MSG=""
[ $((THROTTLE_DEC & (1 << 0))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Under-voltage detected\n"
[ $((THROTTLE_DEC & (1 << 1))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Arm frequency capped\n"
[ $((THROTTLE_DEC & (1 << 2))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Currently throttled\n"
[ $((THROTTLE_DEC & (1 << 3))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Soft temperature limit active\n"
[ $((THROTTLE_DEC & (1 << 16))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Under-voltage has occurred\n"
[ $((THROTTLE_DEC & (1 << 17))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Arm frequency capping has occurred\n"
[ $((THROTTLE_DEC & (1 << 18))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Throttling has occurred\n"
[ $((THROTTLE_DEC & (1 << 19))) -ne 0 ] && THROTTLE_MSG="${THROTTLE_MSG}• Soft temperature limit has occurred\n"


# Start HTML content
cat > "$OUTPUT_FILE" <<'EOF'
<html>
<head>
<title>System Monitoring Report</title>
<meta http-equiv="refresh" content="30">
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  h2 { color: #333; }
  table { width: 100%; border-collapse: collapse; margin-top: 20px; }
  th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
  th { background-color: #f4f4f4; }
</style>
</head>
<body>
<h2>System Monitoring Report</h2>
<p><strong>Hostname:</strong> HOSTNAME_VAL</p>
<p><strong>Uptime:</strong> UPTIME_VAL</p>
<p><strong>CPU Throttling Status:</strong><br>
<pre>THROTTLE_MSG</pre>
</p>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>CPU Load (1, 5, 15 min)</td><td>CPU_LOAD_VAL</td></tr>
<tr><td>Memory Usage</td><td>MEMORY_USAGE_VAL</td></tr>
<tr><td>Disk Usage (Root Partition)</td><td>DISK_USAGE_VAL</td></tr>
<tr><td>Network Interfaces</td><td><ul>
EOF

# Inject dynamic values into placeholders
sed -i \
  -e "s/HOSTNAME_VAL/$HOSTNAME/" \
  -e "s/UPTIME_VAL/$UPTIME/" \
  -e "s/CPU_LOAD_VAL/$CPU_LOAD/" \
  -e "s/MEMORY_USAGE_VAL/$MEMORY_USAGE/" \
  -e "s/DISK_USAGE_VAL/$DISK_USAGE/" \
  -e "s/THROTTLE_MSG/$THROTTLE_MSG/" \
  "$OUTPUT_FILE"

# Add network interfaces without breaking on spaces
while IFS= read -r iface; do
  echo "<li>$iface</li>" >> "$OUTPUT_FILE"
done <<< "$NETWORK_INTERFACES"

cat >> "$OUTPUT_FILE" <<'EOF'
</ul></td></tr>
</table>
<p>Report generated on: DATE_VAL</p>
</body>
</html>
EOF

# Add timestamp
sed -i "s/DATE_VAL/$(date)/" "$OUTPUT_FILE"

# Set correct permissions
chmod 644 $OUTPUT_FILE

# Display message
#echo "System report generated at $OUTPUT_FILE"
