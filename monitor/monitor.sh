#!/bin/bash

# Output HTML file
OUTPUT_FILE="/opt/monitoring/www/html/index.html"

# Upstream DNS servers to test
DNS_UPSTREAMS="208.67.222.222 1.1.1.1 9.9.9.9"
METRICS_LOG="/opt/monitoring/www/html/metrics.log"

append_throttle_message() {
  local target_var="$1"
  local mask="$2"
  local text="$3"

  if (( THROTTLE_DEC & mask )); then
    printf -v "$target_var" '%s%s\n' "${!target_var}" "$text"
  fi
}

check_dns() {
  local server="$1"
  local udp_status="FAIL"
  local tcp_status="FAIL"

  if command -v dig >/dev/null 2>&1; then
    # Query a stable public domain to validate recursive resolution.
    if dig @"$server" cloudflare.com +short +time=2 +tries=1 >/dev/null 2>&1; then
      udp_status="OK"
    fi
    if dig +tcp @"$server" cloudflare.com +short +time=3 +tries=1 >/dev/null 2>&1; then
      tcp_status="OK"
    fi
  else
    udp_status="N/A (dig missing)"
    tcp_status="N/A (dig missing)"
  fi

  echo "$server|$udp_status|$tcp_status"
}

metric_chart() {
  local column="$1"
  local label="$2"
  local tone="$3"
  local cutoff="$4"
  local timezone="$5"
  if [ ! -r "$METRICS_LOG" ]; then
    printf '<span class="trend-empty">No metric history available</span>'
    return
  fi
  awk -F',' -v column="$column" -v label="$label" -v tone="$tone" -v cutoff="$cutoff" -v timezone="$timezone" '
    NR == 1 { next }
    {
      if ($1 < cutoff) next
      value = $column
      gsub(/%/, "", value)
      if (value ~ /^[0-9]+([.][0-9]+)?$/) {
        values[++count] = value + 0
        times[count] = $1
      }
    }
    END {
      if (!count) {
        print "<span class=\"trend-empty\">No samples in the last 24 hours</span>"
        exit
      }
      printf "<div class=\"sparkline\" data-trend-label=\"%s\" role=\"img\" aria-label=\"Recent %s trend\">", tone, label
      for (sample = 1; sample <= count; sample++) {
        height = values[sample]
        sample_time = times[sample]
        sub(/ /, "T", sample_time)
        if (height < 5) height = 5
        if (height > 100) height = 100
        printf "<span class=\"sparkline-bar %s\" data-sample-time=\"%s%s\" data-sample-value=\"%.2f\" style=\"height:%.0f%%\" title=\"%s: %.1f%%\"></span>", tone, sample_time, timezone, values[sample], height, times[sample], values[sample]
      }
      printf "</div>"
    }' "$METRICS_LOG"
}

# Collect system information
HOSTNAME=$(hostname)
UPTIME=$(uptime -p)
CPU_LOAD=$(uptime | sed 's/.*load average: //')
MEMORY_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
PI_TEMP=$(vcgencmd measure_temp | cut -d'=' -f2 | cut -d"'" -f1)
PI_VOLT=$(vcgencmd measure_volts core | cut -d'=' -f2 | cut -d'V' -f1)
NETWORK_INTERFACES=$(ip -o -4 addr show | awk '$2 == "wlan0" || $2 == "eth0" {print $2 " " $4}')
THROTTLE_RAW=$(vcgencmd get_throttled 2>/dev/null)
THROTTLE_HEX=$(echo "$THROTTLE_RAW" | sed -n 's/.*throttled=\(0x[0-9a-fA-F]*\).*/\1/p')

if [ -n "$THROTTLE_HEX" ]; then
  THROTTLE_DEC=$((THROTTLE_HEX))
else
  THROTTLE_DEC=0
  THROTTLE_HEX="0x0"
fi

THROTTLE_CURRENT=""
THROTTLE_HISTORY=""
append_throttle_message THROTTLE_CURRENT $((1 << 0)) "Under-voltage detected now"
append_throttle_message THROTTLE_CURRENT $((1 << 1)) "Arm frequency capped now"
append_throttle_message THROTTLE_CURRENT $((1 << 2)) "Currently throttled"
append_throttle_message THROTTLE_CURRENT $((1 << 3)) "Soft temperature limit active now"
append_throttle_message THROTTLE_HISTORY $((1 << 16)) "Under-voltage has occurred since boot"
append_throttle_message THROTTLE_HISTORY $((1 << 17)) "Arm frequency capping has occurred since boot"
append_throttle_message THROTTLE_HISTORY $((1 << 18)) "Throttling has occurred since boot"
append_throttle_message THROTTLE_HISTORY $((1 << 19)) "Soft temperature limit has occurred since boot"

THROTTLE_SUMMARY="No throttling detected"
if [ -n "$THROTTLE_CURRENT" ]; then
  THROTTLE_SUMMARY="Active throttling or power issue"
elif [ -n "$THROTTLE_HISTORY" ]; then
  THROTTLE_SUMMARY="No active issue, but historical events recorded"
fi

TREND_CUTOFF=$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S')
TREND_TIMEZONE=$(date '+%:z')
CPU_TREND=$(metric_chart 2 "CPU usage" "cpu" "$TREND_CUTOFF" "$TREND_TIMEZONE")
MEMORY_TREND=$(metric_chart 3 "Memory usage" "memory" "$TREND_CUTOFF" "$TREND_TIMEZONE")
DISK_TREND=$(metric_chart 4 "Disk usage" "disk" "$TREND_CUTOFF" "$TREND_TIMEZONE")

FAILED_CHECK_AVAILABLE=0
FAILED_UNITS=""
if command -v systemctl >/dev/null 2>&1; then
  FAILED_CHECK_AVAILABLE=1
  FAILED_UNITS=$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null | awk 'NF {print $1}')
fi
FAILED_COUNT=$(printf '%s\n' "$FAILED_UNITS" | awk 'NF {count++} END {print count+0}')
THROTTLE_ISSUE_COUNT=$(printf '%s\n' "$THROTTLE_CURRENT" | awk 'NF {count++} END {print count+0}')

DNS_RESULTS=""
DNS_ISSUE_ITEMS=""
DNS_FAILURE_COUNT=0
for server in $DNS_UPSTREAMS; do
  IFS='|' read -r upstream udp tcp <<< "$(check_dns "$server")"
  DNS_RESULTS+="$upstream|$udp|$tcp"$'\n'
  if [ "$udp" = "FAIL" ]; then
    DNS_FAILURE_COUNT=$((DNS_FAILURE_COUNT + 1))
    DNS_ISSUE_ITEMS+="<li>UDP DNS check failed for $upstream</li>"
  fi
  if [ "$tcp" = "FAIL" ]; then
    DNS_FAILURE_COUNT=$((DNS_FAILURE_COUNT + 1))
    DNS_ISSUE_ITEMS+="<li>TCP DNS check failed for $upstream</li>"
  fi
done

ISSUE_COUNT=$((FAILED_COUNT + THROTTLE_ISSUE_COUNT + DNS_FAILURE_COUNT))
ISSUE_CLASS="healthy"
ISSUE_SUMMARY="No active failed issues"
if [ "$ISSUE_COUNT" -gt 0 ]; then
  ISSUE_CLASS="warning"
  ISSUE_SUMMARY="$ISSUE_COUNT active issue(s)"
fi

FAILED_UNIT_ITEMS=""
while IFS= read -r failed_unit; do
  [ -n "$failed_unit" ] || continue
  safe_unit=$(printf '%s' "$failed_unit" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
  FAILED_UNIT_ITEMS+="<li>Failed systemd unit: <code>$safe_unit</code></li>"
done <<< "$FAILED_UNITS"

ISSUE_ITEMS=""
while IFS= read -r throttle_msg; do
  [ -n "$throttle_msg" ] && ISSUE_ITEMS+="<li>$throttle_msg</li>"
done <<< "$THROTTLE_CURRENT"
ISSUE_ITEMS+="$FAILED_UNIT_ITEMS$DNS_ISSUE_ITEMS"

# Start HTML content
THROTTLE_CLASS="healthy"
if [ -n "$THROTTLE_CURRENT" ]; then
  THROTTLE_CLASS="warning"
fi

cat > "$OUTPUT_FILE" <<EOF
<!doctype html>
<html lang="en">
<head>
<title>System Monitor · $HOSTNAME</title>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<link rel="icon" type="image/png" sizes="64x64" href="/images/favicon.png">
<meta http-equiv="refresh" content="30">
<style>
:root { color-scheme: light; --ink: #182625; --muted: #65736f; --line: #dbe4df; --paper: #fff; --canvas: #eef3f0; --green: #176d4a; --teal: #0b7165; --amber: #b75a24; --red: #a83226; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--canvas); color: var(--ink); font: 15px/1.5 "Segoe UI", sans-serif; }
.masthead { display: flex; min-height: 174px; align-items: center; justify-content: space-between; gap: 18px; padding: 24px max(20px, calc((100vw - 1360px) / 2)); background: linear-gradient(100deg, #173b35 0%, #173b35 27%, #173b35c4 43%, #173b3560 65%, #173b3520 100%), url('/images/monitoring-header.webp') right center / 64% auto no-repeat; color: #f5fbf8; }
.brand-mark { color: #8ed9c4; font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; }
.masthead h1 { margin: 2px 0 0; font-size: 20px; }
main { max-width: 1400px; margin: 26px auto; padding: 0 20px 36px; }
.page-nav { display: flex; justify-content: flex-end; margin-bottom: 14px; }
.page-nav a { color: var(--teal); font-weight: 650; text-decoration-thickness: 1px; text-underline-offset: 3px; }
.overview { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px 24px; margin-bottom: 18px; }
.eyebrow { margin: 0 0 4px; color: var(--teal); font-size: 11px; font-weight: 700; letter-spacing: .1em; text-transform: uppercase; }
.overview h2 { margin: 0; font-size: 24px; }
.uptime { margin: 3px 0 0; color: var(--muted); }
.health-pill { max-width: 100%; padding: 9px 13px; border: 1px solid; border-radius: 4px; font-weight: 650; }
.health-pill.healthy { border-color: #9ac7aa; background: #e6f3e9; color: #18583f; }
.health-pill.warning { border-color: #e4b482; background: #fff0df; color: #713a16; }
.metric-grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; margin-bottom: 18px; }
.metric { min-width: 0; padding: 15px 16px; border: 1px solid var(--line); border-top: 3px solid var(--teal); border-radius: 5px; background: var(--paper); }
.metric:nth-child(2) { border-top-color: #398a74; }
.metric:nth-child(3) { border-top-color: #708d56; }
.metric:nth-child(4) { border-top-color: #ce8440; }
.metric:nth-child(5) { border-top-color: #557a9a; }
.metric-label { color: var(--muted); font-size: 12px; font-weight: 600; }
.metric-value { margin-top: 5px; font-size: 22px; font-weight: 700; line-height: 1.2; overflow-wrap: anywhere; }
.metric-detail { margin-top: 5px; color: var(--muted); font-size: 11px; }
.trend-panel { margin-bottom: 14px; }
.trend-heading { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px 18px; }
.trend-heading h3 { margin: 0; }
.trend-controls { display: flex; flex-wrap: wrap; gap: 8px 12px; }
.trend-control { display: flex; align-items: center; gap: 6px; color: var(--muted); font-size: 12px; }
.trend-control select { min-height: 34px; padding: 5px 26px 5px 8px; border: 1px solid var(--line); border-radius: 4px; background: var(--paper); color: var(--ink); font: inherit; }
.trend-summary { margin: 7px 0 10px; color: var(--muted); font-size: 12px; }
.trend-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px; }
.trend-card { min-width: 0; }
.trend-label { margin-bottom: 5px; color: var(--muted); font-size: 12px; font-weight: 650; }
.sparkline { display: flex; height: 70px; align-items: flex-end; gap: 3px; padding: 5px 0 0; border-bottom: 1px solid var(--line); }
.sparkline-bar { flex: 1; min-width: 2px; border-radius: 2px 2px 0 0; }
.sparkline-bar.cpu { background: #167b69; }
.sparkline-bar.memory { background: #557a9a; }
.sparkline-bar.disk { background: #c57938; }
.trend-empty { color: var(--muted); font-size: 12px; }
.detail-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(260px, .8fr); gap: 14px; }
.panel { min-width: 0; padding: 17px 18px; border: 1px solid var(--line); border-radius: 5px; background: var(--paper); }
.panel h3 { margin: 0 0 12px; font-size: 16px; }
.panel-intro { margin: -5px 0 12px; color: var(--muted); font-size: 13px; }
.raw-status { display: flex; flex-wrap: wrap; gap: 8px 16px; margin: 0 0 14px; color: var(--muted); font-size: 13px; }
code { padding: 2px 5px; border-radius: 3px; background: #f0f4f2; font: 12px/1.4 ui-monospace, SFMono-Regular, Consolas, monospace; }
.flag-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.flag-grid h4 { margin: 0 0 6px; color: var(--muted); font-size: 11px; letter-spacing: .08em; text-transform: uppercase; }
.flag-grid ul, .interface-list { margin: 0; padding-left: 18px; }
.flag-grid li, .interface-list li { margin: 4px 0; }
.empty-state { color: var(--muted); }
.dns-panel { margin-top: 14px; }
.issue-panel { margin-top: 14px; }
.issue-panel h3 { margin: 0; }
.issue-heading { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px; }
.issue-list { margin: 12px 0 0; padding-left: 20px; }
.issue-list li { margin: 5px 0; }
.issue-status { font-size: 13px; font-weight: 650; }
table { width: 100%; border-collapse: collapse; text-align: left; }
th { padding: 10px 12px; border-bottom: 1px solid var(--line); background: #f5f8f6; color: var(--muted); font-size: 11px; letter-spacing: .06em; text-transform: uppercase; }
td { padding: 11px 12px; border-bottom: 1px solid #e8eeeb; }
tbody tr:last-child td { border-bottom: 0; }
.status { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 650; }
.status::before { width: 7px; height: 7px; border-radius: 50%; background: currentColor; content: ''; }
.ok { color: var(--green); }
.fail { color: var(--red); }
.na { color: var(--muted); }
footer { margin-top: 14px; color: var(--muted); font-size: 12px; }
@media (max-width: 900px) { .metric-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
@media (max-width: 640px) { .masthead { min-height: 145px; padding: 18px 16px; background-size: auto, 100% auto; } .masthead h1 { font-size: 18px; } main { margin: 18px auto; padding: 0 14px 24px; } .overview h2 { font-size: 21px; } .metric-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 9px; } .metric { padding: 12px; } .metric-value { font-size: 19px; } .detail-grid, .trend-grid { grid-template-columns: 1fr; } .flag-grid { grid-template-columns: 1fr; } .dns-panel { overflow-x: auto; } .dns-panel table { min-width: 460px; } }
</style>
</head>
<body>
<header class="masthead">
  <div><div class="brand-mark">Ridewood · Systems</div><h1>System monitor</h1></div>
</header>
<main>
<nav class="page-nav" aria-label="Related pages"><a href="/network.html">Network inventory</a></nav>
<section class="overview" aria-labelledby="host-heading">
  <div><p class="eyebrow">Live status</p><h2 id="host-heading">$HOSTNAME</h2><p class="uptime">Uptime: $UPTIME</p></div>
  <div class="health-pill $ISSUE_CLASS">$ISSUE_SUMMARY</div>
</section>
<section class="metric-grid" aria-label="System metrics">
  <article class="metric"><div class="metric-label">CPU load</div><div class="metric-value">$CPU_LOAD</div><div class="metric-detail">1, 5 and 15 minute averages</div></article>
  <article class="metric"><div class="metric-label">Memory used</div><div class="metric-value">$MEMORY_USAGE</div><div class="metric-detail">Physical memory</div></article>
  <article class="metric"><div class="metric-label">Root disk used</div><div class="metric-value">$DISK_USAGE</div><div class="metric-detail">Root partition</div></article>
  <article class="metric"><div class="metric-label">Temperature</div><div class="metric-value">$PI_TEMP <span>°C</span></div><div class="metric-detail">Board temperature</div></article>
  <article class="metric"><div class="metric-label">Core voltage</div><div class="metric-value">$PI_VOLT <span>V</span></div><div class="metric-detail">Core rail</div></article>
</section>
<section class="panel trend-panel"><div class="trend-heading"><h3>Recent trends</h3>
<div class="trend-controls">
  <label class="trend-control" for="trend-hours">Range<select id="trend-hours"><option value="1">1 hour</option><option value="6">6 hours</option><option value="12" selected>12 hours</option><option value="24">24 hours</option></select></label>
  <label class="trend-control" for="trend-samples">Samples<select id="trend-samples"><option value="12">12</option><option value="24">24</option><option value="48" selected>48</option></select></label>
</div></div>
<p class="trend-summary" id="trend-summary">Last 12 hours · up to 48 samples</p>
<div class="trend-grid">
  <article class="trend-card"><div class="trend-label">CPU usage</div>$CPU_TREND</article>
  <article class="trend-card"><div class="trend-label">Memory used</div>$MEMORY_TREND</article>
  <article class="trend-card"><div class="trend-label">Root disk used</div>$DISK_TREND</article>
</div></section>
<section class="detail-grid">
  <article class="panel"><h3>Power and throttling</h3>
    <p class="raw-status"><span>Raw status <code>$THROTTLE_HEX</code></span><span class="status $THROTTLE_CLASS">$THROTTLE_SUMMARY</span></p>
    <div class="flag-grid">
      <section><h4>Active now</h4><ul>
EOF

if [ -n "$THROTTLE_CURRENT" ]; then
  while IFS= read -r throttle_msg; do
    [ -n "$throttle_msg" ] && printf '<li>%s</li>\n' "$throttle_msg" >> "$OUTPUT_FILE"
  done <<EOF
$THROTTLE_CURRENT
EOF
else
  printf '<li class="empty-state">No active flags</li>\n' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<EOF
      </ul></section>
      <section><h4>Since boot</h4><ul>
EOF

if [ -n "$THROTTLE_HISTORY" ]; then
  while IFS= read -r throttle_msg; do
    [ -n "$throttle_msg" ] && printf '<li>%s</li>\n' "$throttle_msg" >> "$OUTPUT_FILE"
  done <<EOF
$THROTTLE_HISTORY
EOF
else
  printf '<li class="empty-state">No historical flags</li>\n' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<EOF
      </ul></section>
    </div>
  </article>
  <article class="panel"><h3>Network interfaces</h3><ul class="interface-list">
EOF

while IFS= read -r iface; do
  [ -n "$iface" ] && printf '<li>%s</li>\n' "$iface" >> "$OUTPUT_FILE"
done <<EOF
$NETWORK_INTERFACES
EOF

cat >> "$OUTPUT_FILE" <<EOF
  </ul></article>
</section>
<section class="panel dns-panel"><h3>DNS upstream health</h3><p class="panel-intro">UDP and TCP reachability on port 53</p>
<table><thead><tr><th scope="col">Upstream</th><th scope="col">UDP 53</th><th scope="col">TCP 53</th></tr></thead><tbody>
EOF

while IFS='|' read -r upstream udp tcp; do
  [ -n "$upstream" ] || continue

  udp_class="fail"
  tcp_class="fail"

  if [[ "$udp" == "OK" ]]; then
    udp_class="ok"
  elif [[ "$udp" == N/A* ]]; then
    udp_class="na"
  fi

  if [[ "$tcp" == "OK" ]]; then
    tcp_class="ok"
  elif [[ "$tcp" == N/A* ]]; then
    tcp_class="na"
  fi

  printf '<tr><td>%s</td><td><span class="status %s">%s</span></td><td><span class="status %s">%s</span></td></tr>\n' \
    "$upstream" "$udp_class" "$udp" "$tcp_class" "$tcp" >> "$OUTPUT_FILE"
done <<< "$DNS_RESULTS"

cat >> "$OUTPUT_FILE" <<EOF
</tbody></table></section>
<section class="panel issue-panel"><div class="issue-heading"><h3>Issues</h3><span class="issue-status status $ISSUE_CLASS">$ISSUE_SUMMARY</span></div>
EOF

if [ "$ISSUE_COUNT" -gt 0 ]; then
  printf '<ul class="issue-list">%s</ul>\n' "$ISSUE_ITEMS" >> "$OUTPUT_FILE"
else
  printf '<p class="empty-state">No active failed issues found.</p>\n' >> "$OUTPUT_FILE"
fi

if [ "$FAILED_CHECK_AVAILABLE" -eq 0 ]; then
  printf '<p class="empty-state">Failed-service status is unavailable on this host.</p>\n' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<EOF
</section>
<footer>Report generated on $(date '+%Y-%m-%d %H:%M:%S %Z') · Refreshes every 30 seconds</footer>
</main>
EOF

cat >> "$OUTPUT_FILE" <<'SCRIPT'
<script>
(() => {
  const hoursSelect = document.getElementById('trend-hours');
  const samplesSelect = document.getElementById('trend-samples');
  const summary = document.getElementById('trend-summary');
  const validHours = new Set(['1', '6', '12', '24']);
  const validSamples = new Set(['12', '24', '48']);
  try {
    const savedHours = localStorage.getItem('monitor-trend-hours');
    const savedSamples = localStorage.getItem('monitor-trend-samples');
    if (validHours.has(savedHours)) hoursSelect.value = savedHours;
    if (validSamples.has(savedSamples)) samplesSelect.value = savedSamples;
  } catch (error) { /* use defaults when storage is unavailable */ }

  const updateTrends = () => {
    const hours = Number(hoursSelect.value);
    const sampleLimit = Number(samplesSelect.value);
    const cutoff = Date.now() - hours * 60 * 60 * 1000;
    const counts = [];
    document.querySelectorAll('.sparkline').forEach((chart) => {
      const bars = Array.from(chart.querySelectorAll('.sparkline-bar'));
      const inRange = bars.filter((bar) => {
        const timestamp = Date.parse(bar.dataset.sampleTime || '');
        return Number.isFinite(timestamp) && timestamp >= cutoff;
      });
      const selectedIndexes = new Set();
      if (inRange.length <= sampleLimit) {
        inRange.forEach((_, index) => selectedIndexes.add(index));
      } else {
        for (let sample = 0; sample < sampleLimit; sample += 1) {
          selectedIndexes.add(Math.round(sample * (inRange.length - 1) / (sampleLimit - 1)));
        }
      }
      const selected = inRange.filter((_, index) => selectedIndexes.has(index));
      const selectedBars = new Set(selected);
      bars.forEach((bar) => { bar.hidden = !selectedBars.has(bar); });
      const label = chart.closest('.trend-card').querySelector('.trend-label').textContent;
      chart.setAttribute('aria-label', `${label} over the last ${hours} hours`);
      counts.push(`${label}: ${selected.length}`);
    });
    summary.textContent = `Last ${hours} ${hours === 1 ? 'hour' : 'hours'} · ${counts.join(' · ')} samples`;
  };

  const saveSelection = () => {
    try {
      localStorage.setItem('monitor-trend-hours', hoursSelect.value);
      localStorage.setItem('monitor-trend-samples', samplesSelect.value);
    } catch (error) { /* chart controls still work without storage */ }
    updateTrends();
  };
  hoursSelect.addEventListener('change', saveSelection);
  samplesSelect.addEventListener('change', saveSelection);
  updateTrends();
})();
</script>
</body>
</html>
SCRIPT

# Set correct permissions
chmod 644 "$OUTPUT_FILE"

# Display message
#echo "System report generated at $OUTPUT_FILE"
