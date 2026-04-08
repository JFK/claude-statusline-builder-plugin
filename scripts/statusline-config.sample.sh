# shellcheck shell=bash
# ~/.claude/statusline-config.sh
#
# Override defaults for claude-statusline-builder. This file is sourced by
# scripts/statusline-command.sh on every render. Uncomment and edit any line
# below — unset values fall back to the script's built-in defaults.
#
# This file is YOUR personal config — keep it out of version control. The
# plugin's .gitignore already excludes it from the plugin repo.

# ============ Locale / time ============
# export STATUSLINE_TZ="Asia/Tokyo"                 # empty = system default
# STATUSLINE_TZ_LABEL: unset = auto-detect via `date +%Z`. Set to "" to suppress.
# export STATUSLINE_TZ_LABEL=""
# export STATUSLINE_LANG="en"                       # 'ja' enables 月火水木金土日 day-of-week mapping
# export STATUSLINE_DATETIME_FMT="%Y-%m-%d (%a) %H:%M"

# ============ Identity ============
# Defaults to "$USER@$(hostname -s)", collapsed to "$USER" when they match
# export STATUSLINE_USER_HOST="me@laptop"

# ============ Git working-tree state ============
# Appends ●N (modified/untracked), ±N (staged), ↑N (ahead), ↓N (behind)
# to the branch name on line 1. Zero-valued segments are suppressed, so
# a clean repo still renders as "(branch)" with no visual change.
# export GIT_DIRTY_ENABLED=1

# ============ Context-window burn rate ============
# Appends "+12.4k/turn" to the ctx percentage when the context window is
# growing steadily, so you can judge when to /clear before hitting the
# ceiling. Suppressed when the delta is negative (e.g. after /clear) or
# below CTX_BURN_MIN_DELTA tokens to avoid noise.
# export CTX_BURN_ENABLED=1
# export CTX_BURN_WINDOW=5         # samples kept per session
# export CTX_BURN_MIN_DELTA=1000   # tokens/turn — below this, hide the field

# ============ CI status indicator ============
# Appends 🟢ci / 🟡ci / 🔴ci / ⚪ci to the branch on line 1, reflecting the
# latest GitHub Actions run for the current branch. Requires the `gh` CLI
# on PATH and an authenticated session — silently disabled otherwise.
# Cache TTL is short to surface failures fast without hammering rate limits.
# export CI_ENABLED=1
# export CI_TTL=120                # seconds

# ============ Weather (wttr.in) ============
# export WEATHER_ENABLED=1
# export WEATHER_COORDS=""                          # empty = wttr IP-detect; e.g. "37.7749,-122.4194"
# export WEATHER_LANG="en"
# export WEATHER_TTL=1800
#
# Today min/max (inline) + tomorrow / day-after-tomorrow forecast row.
# Set ENABLED=0 to drop both. Forecast cache TTL is longer because forecasts
# change slowly compared to the current-conditions row.
# export WEATHER_FORECAST_ENABLED=1
# export WEATHER_FORECAST_TTL=10800                 # 3 hours

# ============ News ============
# export NEWS_ENABLED=1
# export NEWS_COUNT=5                               # cache up to N, rotate one per render
# export NEWS_TITLE_MAX=72
# export NEWS_TTL=3600

# ============ Service health (Statuspage) ============
# export HEALTH_ENABLED=1
# export HEALTH_TTL=300
# Space-separated list of providers to track:
# export HEALTH_PROVIDERS="anthropic github openai cloudflare"
#
# Cloudflare PoP filter (regex over IATA codes inside parens). Empty = global only.
# export HEALTH_CLOUDFLARE_REGION_FILTER="NRT|KIX|FUK|OKA"   # Japanese PoPs
# export HEALTH_CLOUDFLARE_REGION_FILTER="LAX|SJC|SEA|ORD"   # US west coast
#
# OpenAI components to render in the breakdown line (regex over full names):
# export HEALTH_OPENAI_COMPONENTS="Embeddings|Fine-tuning|Audio|Images|Batch|Moderations"

# ============ Monthly cost ============
# Cost slots are OMITTED entirely when their matching admin key is unset.
# Both keys unset → no cost prefix on the billing line at all.
# export COST_ENABLED=1
# export COST_TTL=3600

# ============ Rendering ============
# export STATUSLINE_BORDER_CHAR="─"
# export STATUSLINE_BORDER_WIDTH=60
# export STATUSLINE_FIELD_SEP="  "                  # double-space between fields
#
# Threshold percentages for the green→yellow→magenta→red color ramp:
# export STATUSLINE_PCT_YELLOW=50
# export STATUSLINE_PCT_MAGENTA=75
# export STATUSLINE_PCT_RED=90
#
# Where TTL'd cache files live:
# export STATUSLINE_CACHE_DIR="/tmp"

# ============ Admin API keys ============
# These can also be set in ~/.profile. The script reads either spelling
# (ANTHROPIC_ADMIN_API_KEY is canonical; ANTHOROPIC_ADMIN_API_KEY is a
# back-compat alias for the typo found in some older configs).
#
# export ANTHROPIC_ADMIN_API_KEY="sk-ant-admin-..."
# export OPENAI_ADMIN_API_KEY="sk-admin-..."
