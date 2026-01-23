#! /usr/bin/python3
import csv, json

csv_path = '/opt/monitoring/www/html/metrics.log'
json_path = '/opt/monitoring/www/html/data/stats.json'

with open(csv_path, newline='') as csvfile:
    reader = csv.DictReader(csvfile)
    # Ensure required keys exist; add 'pi_temp' if missing
    fieldnames = reader.fieldnames or []
    required = ['timestamp', 'cpu_usage', 'memory_usage', 'disk_usage', 'pi_temp']
    data = {key: [] for key in required}

    for row in reader:
        # Timestamp
        data['timestamp'].append(row.get('timestamp', ''))
        # Numeric fields with safe conversion
        def to_float(val):
            try:
                return float(val)
            except (TypeError, ValueError):
                return None

        data['cpu_usage'].append(to_float(row.get('cpu_usage')))
        data['memory_usage'].append(to_float(row.get('memory_usage')))
        data['disk_usage'].append(to_float(row.get('disk_usage')))
        # Temperature may be absent in older logs; include if present
        data['pi_temp'].append(to_float(row.get('pi_temp')))

with open(json_path, 'w') as jsonfile:
    json.dump(data, jsonfile)

