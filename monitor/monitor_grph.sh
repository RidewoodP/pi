#!/bin/bash

# Log file
LOG_FILE="/opt/monitoring/www/html/metrics.log"
HTML_FILE="/opt/monitoring/www/html/index_test.html"

TTIME=$(date "+%Y-%d-%h %H:%M")

# Ensure log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,cpu_usage,memory_usage,disk_usage,pi_temp" > "$LOG_FILE"
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

tail -n +2 "${LOG_FILE}" | awk '
BEGIN { count = 0 }
{
    lines[++count] = $0
}
END {
    output_count = 0
    seen_data = ""  # Track seen timestamps to avoid duplicates
    
    # First 20 lines (most recent, every 5 min) - GREEN
    start = (count > 20) ? count - 19 : 1
    for (i = start; i <= count; i++) {
        ts = lines[i]
        if (!(ts in seen)) {
            output_lines[++output_count] = "G|" lines[i]
            seen[ts] = 1
        }
    }
    
    # Next 10 lines every 30 minutes (every 6 entries at 5-min intervals) - YELLOW
    if (count > 20) {
        skip_count = 0
        for (i = count - 36; i >= 1 && skip_count < 10; i -= 6) {
            ts = lines[i]
            if (!(ts in seen)) {
                output_lines[++output_count] = "B|" lines[i]
                seen[ts] = 1
                skip_count++
            }
        }
    }
    
    # Next 10 lines every 1 hour (every 12 entries at 5-min intervals) - BLUE
    if (count > 60) {
        skip_count = 0
        for (i = count - 72; i >= 1 && skip_count < 10; i -= 12) {
            ts = lines[i]
            if (!(ts in seen)) {
                output_lines[++output_count] = "Y|" lines[i]
                seen[ts] = 1
                skip_count++
            }
        }
    }
    
    # Sort output by timestamp (not by color marker)
    n = output_count
    for (i = 1; i <= n; i++) {
        for (j = i + 1; j <= n; j++) {
            ts_i = substr(output_lines[i], 3);  # Skip color marker
            ts_j = substr(output_lines[j], 3);  # Skip color marker
            if (ts_i > ts_j) {
                temp = output_lines[i]
                output_lines[i] = output_lines[j]
                output_lines[j] = temp
            }
        }
    }
    
    # Print sorted output
    for (i = 1; i <= output_count; i++) {
        print output_lines[i]
    }
}' | tac > "${LOG_FILE}_data"

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
        color_marker = substr($0, 1, 1);
        data = substr($0, 3);
        split(data, fields, ",");
        if (color_marker == "G") color = "<span style=\"color: green;\">";
        else if (color_marker == "Y") color = "<span style=\"color: gold;\">";
        else if (color_marker == "B") color = "<span style=\"color: blue;\">";
        else color = "";
        reset = (color != "") ? "</span>" : "";
        printf color "%-22s |  %-12s |  %-15s |  %-13s |   %-8s " reset "\n", fields[1], fields[2], fields[3], fields[4], fields[5];
    }' "${LOG_FILE}_data"
    echo "</pre>"
    echo "</body>"
    echo "</html>"
} > "$HTML_FILE"

