#!/bin/bash
# tests/forecast-jq.sh
#
# Golden test for the forecast jq filter in scripts/statusline-command.sh.
# Runs the exact same jq expression against synthetic wttr.in j1 payloads and
# asserts the TSV output column-by-column.
#
# Focus: the today_rain(d) helper added for issue #19 should take the MAX
# chanceofrain across today's hourly slots (not just the noon slot), so that
# a rainy morning/evening forecast is not hidden by a dry noon reading.
#
# Run from the plugin root: bash tests/forecast-jq.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/statusline-command.sh"

command -v jq >/dev/null 2>&1 || { echo "jq not installed; skipping"; exit 0; }
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT"; exit 1; }

# Extract the forecast jq program embedded in statusline-command.sh. There are
# multiple jq blocks in the script; the one we want starts at the `def emoji(c):`
# helper and ends at the `] | @tsv` line. awk captures that full range so all
# helper definitions (emoji, noon, rain, today_rain) are included.
JQ_PROGRAM=$(awk '
  /def emoji\(c\):/   { start=1 }
  start               { print }
  start && /\| @tsv$/ { exit }
' "$SCRIPT")

if [ -z "$JQ_PROGRAM" ]; then
  echo "❌ failed to extract jq program from $SCRIPT"
  exit 1
fi

pass=0
fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    printf '  ✅ %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf '  ❌ %s\n    expected: %s\n    actual:   %s\n' "$desc" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

# Build a 3-day forecast fixture where today has a dry noon but rainy evening.
# The hourly array uses 8 3-hour slots, as wttr.in does.
make_hourly() {
  # args: rain0 rain1 rain2 rain3 rain4 rain5 rain6 rain7 (chanceofrain per slot)
  #       code (shared weatherCode for all slots, simplifies the fixture)
  local code=$1; shift
  local out=""
  local t=0
  for r in "$@"; do
    [ -n "$out" ] && out="${out},"
    out="${out}{\"time\":\"${t}\",\"chanceofrain\":\"${r}\",\"weatherCode\":\"${code}\"}"
    t=$((t + 300))
  done
  printf '[%s]' "$out"
}

FIXTURE=$(cat <<EOF
{
  "weather": [
    {
      "mintempC": "17",
      "maxtempC": "23",
      "hourly": $(make_hourly "116" "0" "0" "0" "75" "0" "0" "65" "83")
    },
    {
      "mintempC": "15",
      "maxtempC": "18",
      "hourly": $(make_hourly "353" "80" "80" "80" "70" "81" "60" "50" "40")
    },
    {
      "mintempC": "11",
      "maxtempC": "21",
      "hourly": $(make_hourly "113" "0" "0" "0" "0" "0" "0" "0" "0")
    }
  ]
}
EOF
)

OUTPUT=$(printf '%s' "$FIXTURE" | jq -r "$JQ_PROGRAM")

# Expected TSV columns (see the jq program in statusline-command.sh):
#   0  today.mintempC       → "17"
#   1  today.maxtempC       → "23"
#   2  tomorrow emoji       → 🌨 (weatherCode 353 → 🌧, actually other range)
#   3  tomorrow.mintempC    → "15"
#   4  tomorrow.maxtempC    → "18"
#   5  tomorrow rain (noon) → "81"
#   6  day-after emoji      → ☀️ (weatherCode 113)
#   7  day-after.mintempC   → "11"
#   8  day-after.maxtempC   → "21"
#   9  day-after rain (noon)→ "0"
#  10  today rain (MAX)     → "83"   ← the field this test primarily guards

IFS=$'\t' read -r c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 <<<"$OUTPUT"

echo "=== jq filter output ==="
printf '%s\n' "$OUTPUT"
echo

assert_eq "today.mintempC"              "17"   "$c0"
assert_eq "today.maxtempC"              "23"   "$c1"
assert_eq "tomorrow.mintempC"           "15"   "$c3"
assert_eq "tomorrow.maxtempC"           "18"   "$c4"
assert_eq "tomorrow rain (noon slot)"   "81"   "$c5"
assert_eq "day-after.mintempC"          "11"   "$c7"
assert_eq "day-after.maxtempC"          "21"   "$c8"
assert_eq "day-after rain (noon slot)"  "0"    "$c9"

# The critical assertion: today_rain takes max across all of today's slots (83),
# not the noon slot value (0).
assert_eq "today rain (MAX across day)" "83"   "$c10"

echo
# Also verify the NULL-safe path: an empty hourly array must yield "0".
NULL_FIXTURE='{"weather":[{"mintempC":"10","maxtempC":"15","hourly":[]}]}'
NULL_OUTPUT=$(printf '%s' "$NULL_FIXTURE" | jq -r "$JQ_PROGRAM")
NULL_TODAY_RAIN=$(printf '%s' "$NULL_OUTPUT" | awk -F'\t' '{print $11}')
assert_eq "empty hourly array → today_rain = 0" "0" "$NULL_TODAY_RAIN"

echo
echo "=== Results: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
