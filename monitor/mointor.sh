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
