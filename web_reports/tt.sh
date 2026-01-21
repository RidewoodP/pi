#!/bin/bash
LOG_FILE="/opt/monitoring/www/html/metrics.log"
HTML_FILE="/opt/monitoring/www/html/index_test.html"

# Ensure output directory exists
mkdir -p "$(dirname "$HTML_FILE")"

# Extract and sanitize filter date from QUERY_STRING (expects YYYY-MM-DD)
raw_date=$(printf '%s' "$QUERY_STRING" | sed -n 's/^.*date=\([^&]*\).*$/\1/p')
raw_date=${raw_date//+/ }
filterDate=$(printf '%s' "$raw_date" | tr -d '\r\n')
if [[ ! $filterDate =~ ^[0-9-]{0,10}$ ]]; then
    filterDate=""
fi

# Handle missing log file gracefully
if [[ ! -f "$LOG_FILE" ]]; then
    cat > "$HTML_FILE" <<EOF
<html>
<head><title>System Metrics</title></head>
<body>
<h1>System Metrics Report</h1>
<p>Data File: metrics.log (not found)</p>
</body>
</html>
EOF
    exit 0
fi

{
    cat <<EOF
<html>
<head><title>System Metrics</title></head>
<body>
<h1>System Metrics Report</h1>
<p>Data File: metrics.log</p>
<form method='get'>
    <label for='date'>Filter by Date (YYYY-MM-DD):</label>
    <input type='text' id='date' name='date'>
    <button type='submit'>Search</button>
</form>
<pre>
EOF

    awk -v filterDate="$filterDate" '
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

    cat <<EOF
</pre>
</body>
</html>
EOF
} > "$HTML_FILE"
