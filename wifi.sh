#! /bin/bash

NDATE=$(date +"%e/%b/%Y %H:%M")

# Check if the wireless interface is available
if ! /sbin/iwlist wlan0 scan &>/dev/null; then
    echo "Error: wlan0 interface not found or iwlist command failed."
    exit 1
fi

LINE=$(/sbin/iwlist wlan0 scan | grep -E "Cell|ESSID|Qua" | grep -B2 Dusk | head -n3 | grep  Quality)
QUAL="${LINE##*y=}"             ; QUAL="${QUAL%% Signal level=*}"
LEVL="${LINE##*Signal level=-}" ; LEVL="${LEVL%% *}"

QUAL1="$(echo "${QUAL}" | cut -f1 -d/)"
QUAL2="$(echo "${QUAL}" | cut -f2 -d/)"

# Check for valid quality values
if [[ -z "${QUAL1}" || -z "${QUAL2}" || "${QUAL2}" -eq 0 ]]; then
    echo "Error: Invalid quality values."
    exit 1
fi

# Work out % of quality
QUAL="$(bc -l <<< "scale=1 ; ${QUAL1}/${QUAL2}*100")"

# Output the results
printf "Date: %s, Quality: %.1f%%, Level: %.1f dBm\n" "${NDATE}" "${QUAL}" "${LEVL}"

exit