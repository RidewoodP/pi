#!/bin/bash

# Log file
LOG_FILE="/opt/monitoring/www/html/metrics.log"
HTML_FILE="/opt/monitoring/www/html/index_test.html"

TTIME=$(date "+%Y-%d-%h %H:%M")

# Ensure log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,cpu_usage,memory_usage,disk_usage" > "$LOG_FILE"
fi

# Collect metrics
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
mem_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
#pi_temp=$(/usr/bin/vcgencmd measure_temp | cut -f2 -d=)
pi_temp=$(/usr/bin/vcgencmd measure_temp | cut -f2 -d= | sed "s/.C//" )
echo "$timestamp,$cpu_usage,$mem_usage,$disk_usage,$pi_temp" >> "$LOG_FILE"

/opt/monitoring/csv_to_json.py

tail -n30 "${LOG_FILE}" | grep -Eiv -- "Timestamp|--" > "${LOG_FILE}_data"

{
    echo "<html>"
    echo "<head><title>System Metrics</title>"
    echo "</head>"
    echo "<meta http-equiv='refresh' content='30'>"
    echo "<title>System Monitoring Report</title>"
    echo "<body>"
    echo "<h1>System Metrics Report ${TTIME}</h1>"
    echo "<p>Last reboot: $(uptime -s) $(uptime -p)</p>"
    echo "<pre>"

    awk -v filterDate="$(echo "$QUERY_STRING" | sed -n 's/^.*date=\([^&]*\).*$/\1/p')" '
    BEGIN {
        FS = ",";
        printf "%-22s | %-13s | %-16s | %-14s | %-8s\n", "Timestamp", "CPU Usage (%)", "Memory Usage (%)", "Disk Usage (%)", "Temperature (&deg;C)";
        printf "-----------------------|---------------|------------------|----------------|--------\n";
    }
    NR > 1 {
        printf "%-22s |  %-12s |  %-15s |  %-13s |   %-8s \n", $1, $2, $3, $4, $5 ;
    }' "${LOG_FILE}_data"
    echo "</pre>"
    echo "</body>"
    echo "</html>"
} > "$HTML_FILE"

