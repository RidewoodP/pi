#! /usr/bin/python3
import csv, json

csv_path = '/opt/monitoring/www/html/metrics.log'
json_path = '/opt/monitoring/www/html/data/stats.json'

with open(csv_path, newline='') as csvfile:
    reader = csv.DictReader(csvfile)
    data = {key: [] for key in reader.fieldnames}

    for row in reader:
        data['timestamp'].append(row['timestamp'])
        data['cpu_usage'].append(float(row['cpu_usage']))
        data['memory_usage'].append(float(row['memory_usage']))
        data['disk_usage'].append(float(row['disk_usage']))

with open(json_path, 'w') as jsonfile:
    json.dump(data, jsonfile)

