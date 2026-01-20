#! /bin/bash

NDATE=$(date +"%e/%b/%Y %H:%M")

LINE=$(/sbin/iwlist wlan0 scan | egrep "Cell|ESSID|Qua" | grep -B2 Dusk | head -n3 | grep  Quality)
QUAL=$(echo $LINE | sed 's/.*y=\(.*\) Signal level=.*/\1/')
LEVL=$(echo $LINE | sed 's/.*Signal level=-\(.*\) .*/\1/')

QUAL1=$(echo $QUAL | cut -f1 -d/)
QUAL2=$(echo $QUAL | cut -f2 -d/)
# work out % of quality
QUAL=$(bc -l <<< "scale=1 ; $QUAL1/$QUAL2*100")
#echo ${NDATE},${QUAL},${LEVL}
printf "%s,%.1f,%.1f\n" "${NDATE}" $QUAL $LEVL

#printf "%s,$.2f,%.2f\n" ${NDATE},${QUAL},${LEVL}

exit

