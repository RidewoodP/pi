#! /bin/bash

LINE=$(/sbin/iwlist wlan0 scan | egrep "Cell|ESSID|Qua" | grep -B2 Dusk | head -n3 | grep  Quality)
WIFI=$(echo $LINE | sed 's/.*y=\(.*\) Signal level=-\(.*\) .*/\1,\2/')
echo $(date),$WIFI 2>&1 >> /var/log/wifi.log

exit

