#!/bin/bash

# Output HTML file
OUTPUT_FILE="/opt/monitoring/www/html/index.html"

# Collect system information
HOSTNAME=$(hostname)
UPTIME=$(uptime -p)
CPU_LOAD=$(top -bn1 | grep "load average" | awk '{print $(NF-2), $(NF-1), $(NF)}')
MEMORY_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
NETWORK_INTERFACES=$(ip -o -4 addr show | awk '{print $2 " - " $4}')
UPTIME=$(uptime -p)

# Start HTML content
echo "<html>
<head>
<title>System Monitoring Report</title>
<meta http-equiv='refresh' content='30'>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  h2 { color: #333; }
  table { width: 100%%; border-collapse: collapse; margin-top: 20px; }
  th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
  th { background-color: #f4f4f4; }
</style>
</head>
<body>
<h2>System Monitoring Report</h2>
<p><strong>Hostname:</strong> $HOSTNAME</p>
<p><strong>Uptime:</strong> $UPTIME</p>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>CPU Load (1, 5, 15 min)</td><td>$CPU_LOAD</td></tr>
<tr><td>Memory Usage</td><td>$MEMORY_USAGE</td></tr>
<tr><td>Disk Usage (Root Partition)</td><td>$DISK_USAGE</td></tr>
<tr><td>Uptime</td><td>$UPTIME</td></tr>
<tr><td>Network Interfaces</td><td><ul>" > $OUTPUT_FILE

# Add network interfaces to the HTML file
for iface in $NETWORK_INTERFACES; do
  echo "<li>$iface</li>" >> $OUTPUT_FILE
done

echo "</ul></td></tr>
</table>
<p>Report generated on: $(date)</p>
</body>
</html>" >> $OUTPUT_FILE

# Set correct permissions
chmod 644 $OUTPUT_FILE

# Display message
#echo "System report generated at $OUTPUT_FILE"
