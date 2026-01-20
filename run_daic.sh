#!/bin/bash
#
# Run daic.sh daily, logging to /var/log/daic.log
# Rotate logs and remove files older than 7 days

set -o pipefail

LOG_DIR="/var/log"
LOG_PREFIX="daic"
MAX_LOGS=9
RETENTION_DAYS=7

# Remove old log files
find "$LOG_DIR" -name "${LOG_PREFIX}.*.log" -type f -mtime +${RETENTION_DAYS} -delete

# Rotate logs in reverse order to avoid overwrites
for ((i=MAX_LOGS-1; i>=1; i--)); do
    [[ -f "$LOG_DIR/${LOG_PREFIX}.$i.log" ]] && \
        mv "$LOG_DIR/${LOG_PREFIX}.$i.log" "$LOG_DIR/${LOG_PREFIX}.$((i+1)).log"
done

# Rotate current log to .1.log
[[ -f "$LOG_DIR/${LOG_PREFIX}.log" ]] && \
    mv "$LOG_DIR/${LOG_PREFIX}.log" "$LOG_DIR/${LOG_PREFIX}.1.log"

# Run the script and redirect output to the log file
# script lives in same dir as run_daic.sh
./daic.sh > "$LOG_DIR/${LOG_PREFIX}.log" 2>&1

