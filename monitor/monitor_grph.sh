#!/bin/bash

# Log file
LOG_FILE="/opt/monitoring/www/html/metrics.log"
HTML_FILE="/opt/monitoring/www/html/system_report.html"

# Ensure log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,cpu_usage,memory_usage,disk_usage" > "$LOG_FILE"
fi

# Collect metrics
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
cpu_usage=$(mpstat 1 1 | awk '/Average/ {print 100 - $NF}')
mem_usage=$(free -m | awk '/Mem:/ {printf "%.2f", $3*100/$2 }')
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

echo "$timestamp,$cpu_usage,$mem_usage,$disk_usage" >> "$LOG_FILE"
# Generate HTML report
# Generate HTML report with graph
{
    echo "<html>"
    echo "<head><title>System Metrics</title></head>"
    echo "<body>"
    echo "<h1>System Metrics Report</h1>"
    echo "<p>Data File: metrics.log</p>"
    echo "<form method='get'>"
    echo "    <label for='date'>Filter by Date (YYYY-MM-DD):</label>"
    echo "    <input type='text' id='date' name='date'>"
    echo "    <button type='submit'>Search</button>"
    echo "</form>"
    echo "<pre>"
    echo "Timestamp              | CPU Usage (%) | Memory Usage (%) | Disk Usage (%)"
    echo "-----------------------|---------------|------------------|----------------"
    awk -v filterDate="$(echo "$QUERY_STRING" | sed -n 's/^.*date=\([^&]*\).*$/\1/p')" '
    BEGIN {
        FS = ",";
        printf "%-22s | %-13s | %-16s | %-14s\n", "Timestamp", "CPU Usage (%)", "Memory Usage (%)", "Disk Usage (%)";
        printf "-----------------------|---------------|------------------|----------------\n";
    }
    NR > 1 {
        if (filterDate == "" || $1 ~ filterDate) {
            printf "%-22s | %-13s | %-16s | %-14s\n", $1, $2, $3, $4;
        }
    }' "$LOG_FILE"
    echo "</pre>"
    echo "</body>"
    echo "</html>"
} > "$HTML_FILE"




# Set permissions for the HTML file
chmod 644 "$HTML_FILE"
# Set permissions for the log file
chmod 644 "$LOG_FILE"

