#!/bin/bash
# Script: my-pi-temp.sh
# Purpose: Display the ARM CPU and GPU  temperature of Raspberry Pi 2/3 
# Author: Vivek Gite <www.cyberciti.biz> under GPL v2.x+
# -------------------------------------------------------
cpu=$(</sys/class/thermal/thermal_zone0/temp)
cpu=$((cpu/1000))
gpu=$(vcgencmd measure_temp | sed 's/temp=\(.*\).C/\1/')

echo "$(date) @ $(hostname)"
echo "-------------------------------------------"

printf "GPU %3.2f C\n" $gpu
printf "CPU %3.2f C\n" $cpu

