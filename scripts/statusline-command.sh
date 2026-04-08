#!/bin/bash
# claude-statusline-builder
# https://github.com/JFK/claude-statusline-builder-plugin
#
# Reads Claude Code statusline JSON on stdin, prints a rich multi-line
# statusline on stdout. All external HTTP fetches happen in the background
# with TTL'd file caches, so the foreground render stays fast on every turn.
#
# Configure by editing ~/.claude/statusline-config.sh — see scripts/statusline-config.sample.sh

input=$(cat)

# Debug hook: dump raw input for inspection
if [ "${CLAUDE_STATUSLINE_DEBUG:-0}" = "1" ]; then
  printf '%s' "$input" > /tmp/claude-statusline-debug.json
fi

# ----- Source ~/.profile (admin keys) and user override config -----
# Wrapped so `set -u` in the user's profile cannot kill us.
if [ -z "${ANTHROPIC_ADMIN_API_KEY:-}" ] || [ -z "${OPENAI_ADMIN_API_KEY:-}" ]; then
  [ -r "$HOME/.profile" ] && . "$HOME/.profile" >/dev/null 2>&1
fi
[ -r "$HOME/.claude/statusline-config.sh" ] && . "$HOME/.claude/statusline-config.sh" >/dev/null 2>&1

# Back-compat alias for the typo'd spelling some users have in ~/.profile
: "${ANTHROPIC_ADMIN_API_KEY:=${ANTHOROPIC_ADMIN_API_KEY:-}}"

# ===================== CONFIGURABLE DEFAULTS =====================
# Locale / time
: "${STATUSLINE_TZ:=}"                      # empty = system default
# Label default: unset → auto-detect from `date +%Z` (e.g. JST, PST, CET).
# Set to a literal empty string via config to suppress the suffix entirely.
if [ -z "${STATUSLINE_TZ_LABEL+x}" ]; then
  if [ -n "$STATUSLINE_TZ" ]; then
    STATUSLINE_TZ_LABEL="$(TZ="$STATUSLINE_TZ" date +%Z 2>/dev/null)"
  else
    STATUSLINE_TZ_LABEL="$(date +%Z 2>/dev/null)"
  fi
fi
: "${STATUSLINE_LANG:=en}"                  # 'ja' enables 月火水木金土日 day-of-week mapping
: "${STATUSLINE_DATETIME_FMT:=%Y-%m-%d (%a) %H:%M}"

# Weather (wttr.in)
: "${WEATHER_ENABLED:=1}"
: "${WEATHER_COORDS:=}"                     # empty = wttr.in IP-detect
: "${WEATHER_LANG:=en}"
: "${WEATHER_TTL:=1800}"
: "${WEATHER_FORECAST_ENABLED:=1}"          # 0 to skip the today min/max + tomorrow/day-after forecast row
: "${WEATHER_FORECAST_TTL:=10800}"          # forecast changes slowly — 3h cache

# News (anthropic.com/news, scraped via python3 if available)
: "${NEWS_ENABLED:=1}"
: "${NEWS_COUNT:=5}"
: "${NEWS_TITLE_MAX:=72}"
: "${NEWS_TTL:=3600}"

# Service health (Statuspage summary endpoints)
: "${HEALTH_ENABLED:=1}"
: "${HEALTH_TTL:=300}"
: "${HEALTH_PROVIDERS:=anthropic github openai cloudflare}"
: "${HEALTH_CLOUDFLARE_REGION_FILTER:=}"    # e.g. 'NRT|KIX|FUK|OKA' to keep specific PoPs
: "${HEALTH_OPENAI_COMPONENTS:=Embeddings|Fine-tuning|Audio|Images|Batch|Moderations}"

# Monthly cost (admin APIs — slot is OMITTED if matching key is unset)
: "${COST_ENABLED:=1}"
: "${COST_TTL:=3600}"

# Rendering
: "${STATUSLINE_BORDER_CHAR:=─}"
: "${STATUSLINE_BORDER_WIDTH:=60}"
: "${STATUSLINE_FIELD_SEP:=  }"             # double-space between fields
: "${STATUSLINE_PCT_YELLOW:=50}"
: "${STATUSLINE_PCT_MAGENTA:=75}"
: "${STATUSLINE_PCT_RED:=90}"
: "${STATUSLINE_USER_HOST:=}"               # empty = "$USER@$(hostname -s)"
: "${STATUSLINE_CACHE_DIR:=/tmp}"

# Git working-tree state (●N modified ±N staged ↑N ahead ↓N behind next to branch)
: "${GIT_DIRTY_ENABLED:=1}"

# Context-window burn rate (+X.Xk/turn next to ctx percentage)
: "${CTX_BURN_ENABLED:=1}"
: "${CTX_BURN_WINDOW:=5}"        # samples kept per session
: "${CTX_BURN_MIN_DELTA:=1000}"  # tokens/turn — below this, suppress to avoid noise

# CI status indicator (🟢/🟡/🔴 next to branch on line 1)
# Requires `gh` CLI on PATH and an authenticated session. Skipped silently when missing.
: "${CI_ENABLED:=1}"
: "${CI_TTL:=120}"               # 2 min — friendly to GitHub rate limits

# One-shot mode override (used by /preview; does NOT touch the flag file)
: "${CLAUDE_STATUSLINE_FORCE_MODE:=}"       # 'minimal' | 'detail' | ''
# =================================================================

# Resolve mode: env override > flag file > default detail
if [ -n "$CLAUDE_STATUSLINE_FORCE_MODE" ]; then
  mode="$CLAUDE_STATUSLINE_FORCE_MODE"
elif [ -f "$HOME/.claude/cache/statusline-minimal" ]; then
  mode="minimal"
else
  mode="detail"
fi

# Identity prefix is resolved later, once $cwd and $git_project are known,
# so the "user@host" collapse can fall back to a pwd basename outside git.

# Cache file paths (all under $STATUSLINE_CACHE_DIR)
CACHE_PREFIX="${STATUSLINE_CACHE_DIR}/claude-statusline"
CTX_HISTORY="${CACHE_PREFIX}-ctx-history"
WEATHER_CACHE="${CACHE_PREFIX}-weather"
WEATHER_FORECAST_CACHE="${CACHE_PREFIX}-weather-forecast"
NEWS_CACHE="${CACHE_PREFIX}-anthropic-news"
NEWS_IDX_FILE="${CACHE_PREFIX}-anthropic-news.idx"
COST_CACHE="${CACHE_PREFIX}-monthly-cost"
ANT_HEALTH_CACHE="${CACHE_PREFIX}-anthropic-health"
ANT_COMP_CACHE="${CACHE_PREFIX}-anthropic-components"
GH_HEALTH_CACHE="${CACHE_PREFIX}-github-health"
GH_COMP_CACHE="${CACHE_PREFIX}-github-components"
OAI_HEALTH_CACHE="${CACHE_PREFIX}-openai-health"
OAI_COMP_CACHE="${CACHE_PREFIX}-openai-components"
CF_HEALTH_CACHE="${CACHE_PREFIX}-cloudflare-health"
CF_COMP_CACHE="${CACHE_PREFIX}-cloudflare-components"

# ----- Helpers -----

# Date wrapper that tries GNU `date -d` then BSD `date -r`, optionally with TZ
# Usage: tzdate "@1700000000" "+%H:%M"
tzdate() {
  local arg="$1" fmt="$2"
  if [ -n "$STATUSLINE_TZ" ]; then
    TZ="$STATUSLINE_TZ" date -d "$arg" "$fmt" 2>/dev/null \
      || TZ="$STATUSLINE_TZ" date -r "${arg#@}" "$fmt" 2>/dev/null
  else
    date -d "$arg" "$fmt" 2>/dev/null \
      || date -r "${arg#@}" "$fmt" 2>/dev/null
  fi
}

# Human-readable token count: 1234 → 1.2k, 1234567 → 1.2M
fmt_k() {
  local n=$1
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1fM\", $n/1000000}"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1fk\", $n/1000}"
  else
    printf "%d" "$n"
  fi
}

# ANSI color escape for a percentage value (configurable thresholds)
pct_color() {
  local p=$1
  if   [ "$p" -ge "$STATUSLINE_PCT_RED" ]     2>/dev/null; then printf '\033[01;31m'  # bold red
  elif [ "$p" -ge "$STATUSLINE_PCT_MAGENTA" ] 2>/dev/null; then printf '\033[35m'     # magenta
  elif [ "$p" -ge "$STATUSLINE_PCT_YELLOW" ]  2>/dev/null; then printf '\033[33m'     # yellow
  else                                                          printf '\033[32m'     # green
  fi
}
RST=$'\033[0m'

# Pick an icon for a Statuspage component status
comp_icon() {
  case "$1" in
    operational)          printf "🟢" ;;
    degraded_performance) printf "🟡" ;;
    partial_outage)       printf "🟠" ;;
    major_outage)         printf "🔴" ;;
    under_maintenance)    printf "🔧" ;;
    *)                    printf "⚪" ;;
  esac
}

# Pick an icon for a Statuspage indicator
indicator_icon() {
  case "$1" in
    none)        printf "🟢" ;;
    minor)       printf "🟡" ;;
    major)       printf "🟠" ;;
    critical)    printf "🔴" ;;
    maintenance) printf "🔧" ;;
    *)           printf "⚪" ;;
  esac
}

# ----- Parse stdin JSON in one jq call -----
# Sentinel "-" for missing strings; sentinel 0 for missing numerics.
# bash collapses adjacent tabs in @tsv with empty strings — use sentinels not "".
# current_usage.* fields were used for the old sess: display (removed in
# v0.1.2 — see CHANGELOG). If/when a per-turn cost or cache-efficiency field
# gets added, re-extract them here.
IFS=$'\t' read -r cwd model_id model_display \
        ctx_window used_pct \
        five_pct five_rst week_pct week_rst \
        session_id \
  < <(printf '%s' "$input" | jq -r '[
      (.cwd                                                      // "-"),
      (.model.id                                                 // "-"),
      (.model.display_name                                       // "-"),
      (.context_window.context_window_size                       // 0),
      (.context_window.used_percentage                           // 0),
      (.rate_limits.five_hour.used_percentage                    // 0),
      (.rate_limits.five_hour.resets_at                          // 0),
      (.rate_limits.seven_day.used_percentage                    // 0),
      (.rate_limits.seven_day.resets_at                          // 0),
      (.session_id                                               // "-")
    ] | @tsv' 2>/dev/null)

# Convert sentinels back to empty
[ "$cwd" = "-" ]           && cwd=""
[ "$model_id" = "-" ]      && model_id=""
[ "$model_display" = "-" ] && model_display=""
[ "$ctx_window" = "0" ]    && ctx_window=""
[ "$used_pct" = "0" ]      && used_pct=""
[ "$five_pct" = "0" ]      && five_pct=""
[ "$week_pct" = "0" ]      && week_pct=""
[ "$five_rst" = "0" ]      && five_rst=""
[ "$week_rst" = "0" ]      && week_rst=""
[ "$session_id" = "-" ]    && session_id=""

# ----- Model display name -----
canonical_name=""
if [ -n "$model_id" ]; then
  ctx_variant=""
  if   echo "$model_id" | grep -qiE '[\[_-]1m[\]_-]?$|1m$';   then ctx_variant=" (1M)"
  elif echo "$model_id" | grep -qiE '[\[_-]200k[\]_-]?$|200k$'; then ctx_variant=" (200K)"
  elif echo "$model_id" | grep -qiE '[\[_-]128k[\]_-]?$|128k$'; then ctx_variant=" (128K)"
  fi
  stripped=$(echo "$model_id" | sed 's/^claude-//i; s/[\[_-]\?[0-9]*[mk][\]]*$//i; s/-[0-9]\{8,\}$//')
  canonical_name=$(echo "$stripped" | awk '{
    n = split($0, parts, "-")
    out = ""
    for (i=1; i<=n; i++) {
      w = parts[i]
      if (w ~ /^[a-zA-Z]/) { w = toupper(substr(w,1,1)) substr(w,2) }
      if (w ~ /^[0-9]/ && out != "") { out = out "." w }
      else { out = (out == "") ? w : out " " w }
    }
    print out
  }')
  canonical_name="Claude ${canonical_name}${ctx_variant}"
fi

chosen_name="$model_display"
if [ -z "$chosen_name" ] || ! echo "$chosen_name" | grep -q ' '; then
  [ -n "$canonical_name" ] && chosen_name="$canonical_name"
fi
if [ -n "$chosen_name" ] && ! echo "$chosen_name" | grep -qi '^claude '; then
  chosen_name="Claude ${chosen_name}"
fi
model_part="${chosen_name:-Claude}"

# ----- Git branch + project name -----
git_branch=""
git_project=""
if [ -n "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  remote_url=$(git -C "$cwd" --no-optional-locks config --get remote.origin.url 2>/dev/null)
  if [ -n "$remote_url" ]; then
    git_project=$(basename "$remote_url" .git)
  else
    toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
    [ -n "$toplevel" ] && git_project=$(basename "$toplevel")
  fi
fi

# ----- Git working-tree state (appended to branch on line 1) -----
# ●N = modified/untracked in working tree, ±N = staged, ↑N = ahead, ↓N = behind.
# Zero-valued segments are suppressed, so a clean repo renders as "(branch)".
git_state=""
if [ "${GIT_DIRTY_ENABLED:-1}" = "1" ] && [ -n "$git_branch" ]; then
  _dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  _staged=0
  _modified=0
  if [ -n "$_dirty" ]; then
    _staged=$(printf '%s\n' "$_dirty" | grep -cE '^[MARCD]' || :)
    _modified=$(printf '%s\n' "$_dirty" | grep -cE '^.[MD]|^\?\?' || :)
  fi

  _ahead=0
  _behind=0
  if git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    _counts=$(git -C "$cwd" --no-optional-locks rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
    if [ -n "$_counts" ]; then
      _behind=$(echo "$_counts" | awk '{print $1}')
      _ahead=$(echo "$_counts" | awk '{print $2}')
    fi
  fi

  [ "$_modified" -gt 0 ] && git_state="${git_state} ●${_modified}"
  [ "$_staged" -gt 0 ] && git_state="${git_state} ±${_staged}"
  [ "$_ahead" -gt 0 ] && git_state="${git_state} ↑${_ahead}"
  [ "$_behind" -gt 0 ] && git_state="${git_state} ↓${_behind}"

  unset _dirty _staged _modified _ahead _behind _counts
fi

# ----- CI status indicator (cache filename + background fetch) -----
# Per-repo cache, keyed by a cksum of the remote URL so multiple repos on
# the same machine never collide. The actual fetch and read happen later,
# below the cache_age helper definition.
CI_CACHE=""
if [ "${CI_ENABLED:-1}" = "1" ] && [ -n "$git_branch" ] && [ -n "$remote_url" ]; then
  _ci_hash=$(printf '%s' "$remote_url" | cksum 2>/dev/null | awk '{print $1}')
  [ -n "$_ci_hash" ] && CI_CACHE="${CACHE_PREFIX}-ci-${_ci_hash}"
  unset _ci_hash
fi

# Resolve identity prefix.
#   user != host          → "user@host"
#   user == host + in git → "user"            (git_project provides context)
#   user == host + no git → "user@<pwd name>" (pwd basename provides context)
if [ -z "$STATUSLINE_USER_HOST" ]; then
  _u="$(whoami 2>/dev/null || echo user)"
  _h="$(hostname -s 2>/dev/null || echo host)"
  if [ "$_u" != "$_h" ]; then
    STATUSLINE_USER_HOST="$_u@$_h"
  elif [ -n "$git_project" ]; then
    STATUSLINE_USER_HOST="$_u"
  elif [ -n "$cwd" ]; then
    STATUSLINE_USER_HOST="$_u@$(basename "$cwd")"
  else
    STATUSLINE_USER_HOST="$_u"
  fi
  unset _u _h
fi

shorten_branch() {
  local b="$1"
  if [ ${#b} -gt 50 ]; then echo "${b:0:47}..."
  else echo "$b"
  fi
}
short_branch=""
[ -n "$git_branch" ] && short_branch=$(shorten_branch "$git_branch")

# ----- Context window usage -----
# Note: a per-turn `sess:` field was removed in v0.1.2 — it was the sum of
# input + output + cache_read_input_tokens and duplicated ctx: within ~1k
# of rounding noise because prefix caching routes almost all context through
# cache_read. If you want a cache-efficiency or per-turn-cost signal instead,
# open a feature request with your preferred semantics.
ctx_part=""
if [ -n "$used_pct" ] && [ -n "$ctx_window" ]; then
  used_tokens=$(awk "BEGIN{printf \"%.0f\", $ctx_window * $used_pct / 100}")
  used_k=$(fmt_k "$used_tokens")
  total_k=$(fmt_k "$ctx_window")
  pct_int=$(printf '%.0f' "$used_pct")
  ctx_color=$(pct_color "$pct_int")

  # ----- Context-window burn rate (+X.Xk/turn) -----
  # Per-session sliding window of recent ctx_token samples. On each render
  # we append the current sample, trim to CTX_BURN_WINDOW per session, and
  # report (current - oldest) / sample_gap as the average tokens-per-turn.
  # Suppressed when negative (e.g. /clear) or below CTX_BURN_MIN_DELTA.
  ctx_burn_part=""
  if [ "${CTX_BURN_ENABLED:-1}" = "1" ] && [ -n "$session_id" ] && [ "$used_tokens" -gt 0 ] 2>/dev/null; then
    _now=$(date +%s)
    _new_line=$(printf '%s\t%s\t%s' "$session_id" "$_now" "$used_tokens")

    # Pull existing samples for this session, append the new one, keep last N
    _session_lines=""
    [ -f "$CTX_HISTORY" ] && _session_lines=$(grep -F "${session_id}	" "$CTX_HISTORY" 2>/dev/null || :)
    if [ -n "$_session_lines" ]; then
      _session_lines=$(printf '%s\n%s\n' "$_session_lines" "$_new_line" | tail -n "${CTX_BURN_WINDOW:-5}")
    else
      _session_lines="$_new_line"
    fi

    # Compute delta from the oldest entry in the trimmed window
    _sample_count=$(printf '%s\n' "$_session_lines" | wc -l | tr -d ' ')
    if [ "$_sample_count" -ge 2 ] 2>/dev/null; then
      _oldest=$(printf '%s\n' "$_session_lines" | head -1 | awk -F'\t' '{print $3}')
      _gap=$((_sample_count - 1))
      if [ "${_oldest:-0}" -gt 0 ] 2>/dev/null && [ "$_gap" -gt 0 ]; then
        _delta=$(( (used_tokens - _oldest) / _gap ))
        if [ "$_delta" -ge "${CTX_BURN_MIN_DELTA:-1000}" ] 2>/dev/null; then
          ctx_burn_part=" +$(fmt_k "$_delta")/turn"
        fi
      fi
    fi

    # Persist: rewrite the history file, replacing this session's slice and
    # leaving other sessions intact. Atomic via temp + mv.
    _other_sessions=""
    [ -f "$CTX_HISTORY" ] && _other_sessions=$(grep -vF "${session_id}	" "$CTX_HISTORY" 2>/dev/null || :)
    _tmp="${CTX_HISTORY}.tmp.$$"
    {
      [ -n "$_other_sessions" ] && printf '%s\n' "$_other_sessions"
      printf '%s\n' "$_session_lines"
    } > "$_tmp" 2>/dev/null && mv "$_tmp" "$CTX_HISTORY" 2>/dev/null

    unset _now _new_line _session_lines _sample_count _oldest _gap _delta _other_sessions _tmp
  fi

  ctx_part="ctx:${used_k}/${total_k}(${ctx_color}${pct_int}%${RST}${ctx_burn_part})"
fi

# ----- Rate limit reset formatting -----
fmt_reset_time() {
  local epoch=$1
  [ -z "$epoch" ] && return
  local t
  t=$(tzdate "@$epoch" "+%H:%M")
  [ -z "$t" ] && return
  if [ -n "$STATUSLINE_TZ_LABEL" ]; then
    printf "%s %s" "$t" "$STATUSLINE_TZ_LABEL"
  else
    printf "%s" "$t"
  fi
}

fmt_reset_dow_time() {
  local epoch=$1
  [ -z "$epoch" ] && return
  local raw_day raw_time
  raw_day=$(tzdate "@$epoch" "+%a")
  raw_time=$(tzdate "@$epoch" "+%H:%M")
  [ -z "$raw_time" ] && return
  local day="$raw_day"
  if [ "$STATUSLINE_LANG" = "ja" ]; then
    case "$raw_day" in
      Mon) day="月" ;; Tue) day="火" ;; Wed) day="水" ;;
      Thu) day="木" ;; Fri) day="金" ;; Sat) day="土" ;;
      Sun) day="日" ;;
    esac
  fi
  if [ -n "$STATUSLINE_TZ_LABEL" ]; then
    printf "%s %s %s" "$day" "$raw_time" "$STATUSLINE_TZ_LABEL"
  else
    printf "%s %s" "$day" "$raw_time"
  fi
}

# ----- Rate limit display -----
rate_part=""
if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
  rate_items=()
  if [ -n "$five_pct" ]; then
    five_pct_int=$(printf '%.0f' "$five_pct")
    five_color=$(pct_color "$five_pct_int")
    if [ "$five_pct_int" -gt 100 ] 2>/dev/null; then
      part="5h:${five_color}100%+${RST}"
    else
      part="5h:${five_color}${five_pct_int}%${RST}"
    fi
    rst=$(fmt_reset_time "$five_rst")
    [ -n "$rst" ] && part="${part} → ${rst}"
    rate_items+=("$part")
  fi
  if [ -n "$week_pct" ]; then
    week_pct_int=$(printf '%.0f' "$week_pct")
    week_color=$(pct_color "$week_pct_int")
    if [ "$week_pct_int" -gt 100 ] 2>/dev/null; then
      part="7d:${week_color}100%+${RST}"
    else
      part="7d:${week_color}${week_pct_int}%${RST}"
    fi
    if [ -n "$week_rst" ] && [ "$week_rst" -gt 0 ] 2>/dev/null; then
      rst=$(fmt_reset_dow_time "$week_rst")
      [ -n "$rst" ] && part="${part} → ${rst}"
    fi
    rate_items+=("$part")
  fi
  joined=""
  for item in "${rate_items[@]}"; do
    if [ -z "$joined" ]; then
      joined="$item"
    else
      joined="${joined}${STATUSLINE_FIELD_SEP}${item}"
    fi
  done
  rate_part="$joined"
fi

# ----- Cache age helper -----
cache_age() {
  local f=$1
  echo $(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0) ))
}

# ----- Background fetch: GitHub Actions CI status for current branch -----
# Skipped silently when `gh` is missing, the repo has no remote, or we're
# not in a git checkout. Cache schema is one line: "<status>\t<conclusion>".
# When the branch has no runs, jq emits nothing and the cache file is left
# untouched (the previous value, if any, persists until the next refresh).
if [ -n "$CI_CACHE" ] && command -v gh >/dev/null 2>&1; then
  age=$(cache_age "$CI_CACHE")
  if [ ! -f "$CI_CACHE" ] || [ "$age" -gt "${CI_TTL:-120}" ]; then
    (
      cd "$cwd" 2>/dev/null || exit 0
      gh run list --branch "$git_branch" --limit 1 \
        --json status,conclusion \
        --jq 'if length > 0 then .[0] | "\(.status)\t\(.conclusion // "-")" else empty end' 2>/dev/null \
        > "${CI_CACHE}.tmp"
      if [ -s "${CI_CACHE}.tmp" ]; then
        mv "${CI_CACHE}.tmp" "$CI_CACHE"
      else
        rm -f "${CI_CACHE}.tmp"
      fi
    ) >/dev/null 2>&1 & disown
  fi
fi

# ----- Background fetch: Anthropic health -----
in_providers() {
  case " $HEALTH_PROVIDERS " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

if [ "$HEALTH_ENABLED" = "1" ] && in_providers anthropic; then
  age=$(cache_age "$ANT_HEALTH_CACHE")
  if [ ! -f "$ANT_HEALTH_CACHE" ] || [ "$age" -gt "$HEALTH_TTL" ]; then
    (
      summary=$(curl -fsS -L --max-time 4 "https://status.claude.com/api/v2/summary.json" 2>/dev/null)
      if [ -n "$summary" ]; then
        echo "$summary" | jq -r '.status.indicator // "unknown"' \
          > "${ANT_HEALTH_CACHE}.tmp" && mv "${ANT_HEALTH_CACHE}.tmp" "$ANT_HEALTH_CACHE"
        echo "$summary" | jq -r '
          .components[]
          | (.name
              | sub("^claude\\.ai$"; "ai")
              | sub("^platform\\.claude\\.com.*$"; "platform")
              | sub("^Claude API.*$"; "api")
              | sub("^Claude Code$"; "code")
              | sub("^Claude Cowork$"; "cowork")
              | sub("^Claude for Government$"; "gov")
            ) + "\t" + .status' \
          > "${ANT_COMP_CACHE}.tmp" && mv "${ANT_COMP_CACHE}.tmp" "$ANT_COMP_CACHE"
      fi
    ) >/dev/null 2>&1 & disown
  fi
fi

# ----- Background fetch: GitHub health -----
if [ "$HEALTH_ENABLED" = "1" ] && in_providers github; then
  age=$(cache_age "$GH_HEALTH_CACHE")
  if [ ! -f "$GH_HEALTH_CACHE" ] || [ "$age" -gt "$HEALTH_TTL" ]; then
    (
      summary=$(curl -fsS -L --max-time 4 "https://www.githubstatus.com/api/v2/summary.json" 2>/dev/null)
      if [ -n "$summary" ]; then
        echo "$summary" | jq -r '.status.indicator // "unknown"' \
          > "${GH_HEALTH_CACHE}.tmp" && mv "${GH_HEALTH_CACHE}.tmp" "$GH_HEALTH_CACHE"
        echo "$summary" | jq -r '
          .components[]
          | select(.group_id == null)
          | select(.name | test("^Visit ") | not)
          | (.name
              | sub("^Git Operations$"; "git")
              | sub("^Webhooks$"; "hook")
              | sub("^API Requests$"; "api")
              | sub("^Issues$"; "iss")
              | sub("^Pull Requests$"; "pr")
              | sub("^Actions$"; "act")
              | sub("^Packages$"; "pkg")
              | sub("^Pages$"; "page")
              | sub("^Codespaces$"; "cs")
              | sub("^Copilot$"; "cop")
            ) + "\t" + .status' \
          > "${GH_COMP_CACHE}.tmp" && mv "${GH_COMP_CACHE}.tmp" "$GH_COMP_CACHE"
      fi
    ) >/dev/null 2>&1 & disown
  fi
fi

# ----- Background fetch: OpenAI health -----
if [ "$HEALTH_ENABLED" = "1" ] && in_providers openai; then
  age=$(cache_age "$OAI_HEALTH_CACHE")
  if [ ! -f "$OAI_HEALTH_CACHE" ] || [ "$age" -gt "$HEALTH_TTL" ]; then
    (
      summary=$(curl -fsS -L --max-time 4 "https://status.openai.com/api/v2/summary.json" 2>/dev/null)
      if [ -n "$summary" ]; then
        echo "$summary" | jq -r '.status.indicator // "unknown"' \
          > "${OAI_HEALTH_CACHE}.tmp" && mv "${OAI_HEALTH_CACHE}.tmp" "$OAI_HEALTH_CACHE"
        # Filter to the configured component list (regex), then short-name
        echo "$summary" | jq -r --arg pat "$HEALTH_OPENAI_COMPONENTS" '
          .components[]
          | select(.group_id == null)
          | select(.name | test("^(" + $pat + ")$"))
          | (.name
              | sub("^Embeddings$"; "embed")
              | sub("^Fine-tuning$"; "ft")
              | sub("^Audio$"; "audio")
              | sub("^Images$"; "img")
              | sub("^Batch$"; "batch")
              | sub("^Moderations$"; "mod")
            ) + "\t" + .status' \
          > "${OAI_COMP_CACHE}.tmp" && mv "${OAI_COMP_CACHE}.tmp" "$OAI_COMP_CACHE"
      fi
    ) >/dev/null 2>&1 & disown
  fi
fi

# ----- Background fetch: Cloudflare health -----
if [ "$HEALTH_ENABLED" = "1" ] && in_providers cloudflare; then
  age=$(cache_age "$CF_HEALTH_CACHE")
  if [ ! -f "$CF_HEALTH_CACHE" ] || [ "$age" -gt "$HEALTH_TTL" ]; then
    (
      summary=$(curl -fsS -L --max-time 4 "https://www.cloudflarestatus.com/api/v2/summary.json" 2>/dev/null)
      if [ -n "$summary" ]; then
        echo "$summary" | jq -r '.status.indicator // "unknown"' \
          > "${CF_HEALTH_CACHE}.tmp" && mv "${CF_HEALTH_CACHE}.tmp" "$CF_HEALTH_CACHE"
        # Always include the global services row; if the user set a region
        # filter, also include any PoP whose name contains an IATA code from
        # the regex.
        echo "$summary" | jq -r --arg regions "$HEALTH_CLOUDFLARE_REGION_FILTER" '
          .components[]
          | select(
              .name == "Cloudflare Sites and Services"
              or ($regions != "" and (.name | test("\\((" + $regions + ")\\)")))
            )
          | (.name
              | sub("^Cloudflare Sites and Services$"; "svc")
              | gsub("^.*\\(([A-Z]{3})\\)$"; "\\1")
            ) + "\t" + .status' \
          > "${CF_COMP_CACHE}.tmp" && mv "${CF_COMP_CACHE}.tmp" "$CF_COMP_CACHE"
      fi
    ) >/dev/null 2>&1 & disown
  fi
fi

# ----- Read cached CI status and map to a glyph -----
ci_segment=""
if [ -n "$CI_CACHE" ] && [ -f "$CI_CACHE" ] && [ -s "$CI_CACHE" ]; then
  IFS=$'\t' read -r _ci_status _ci_conclusion < "$CI_CACHE"
  case "$_ci_status" in
    completed)
      case "$_ci_conclusion" in
        success)                       ci_segment=" 🟢ci" ;;
        failure|cancelled|timed_out)   ci_segment=" 🔴ci" ;;
        skipped|neutral|action_required|stale) ci_segment=" ⚪ci" ;;
      esac
      ;;
    in_progress|queued|requested|waiting|pending) ci_segment=" 🟡ci" ;;
  esac
  unset _ci_status _ci_conclusion
fi

# ----- Read cached health values -----
read_indicator() {
  local f=$1
  [ -f "$f" ] && [ -s "$f" ] && tr -d '\n' < "$f"
}
ant_indicator=$(read_indicator "$ANT_HEALTH_CACHE")
gh_indicator=$(read_indicator "$GH_HEALTH_CACHE")
oai_indicator=$(read_indicator "$OAI_HEALTH_CACHE")
cf_indicator=$(read_indicator "$CF_HEALTH_CACHE")

# Build per-provider compact prefixes (model line) and breakdown lines
ant_prefix=""
[ -n "$ant_indicator" ] && ant_prefix=$(indicator_icon "$ant_indicator")

extra_health_prefix=""
if [ -n "$gh_indicator" ];  then extra_health_prefix="${extra_health_prefix}$(indicator_icon "$gh_indicator")gh "; fi
if [ -n "$cf_indicator" ];  then extra_health_prefix="${extra_health_prefix}$(indicator_icon "$cf_indicator")cf "; fi
if [ -n "$oai_indicator" ]; then extra_health_prefix="${extra_health_prefix}$(indicator_icon "$oai_indicator")oai "; fi

# Breakdown line builders
build_breakdown() {
  local cache=$1 sep=$2
  [ -f "$cache" ] && [ -s "$cache" ] || return 1
  local parts="" name status icon
  while IFS=$'\t' read -r name status; do
    [ -z "$name" ] && continue
    icon=$(comp_icon "$status")
    if [ -z "$parts" ]; then parts="${icon}${name}"
    else parts="${parts}${sep}${icon}${name}"
    fi
  done < "$cache"
  printf '%s' "$parts"
}

ant_alert=""
if [ -n "$ant_indicator" ] && [ "$ant_indicator" != "none" ]; then
  parts=$(build_breakdown "$ANT_COMP_CACHE" "  ")
  [ -n "$parts" ] && ant_alert="${parts} → https://status.claude.com"
fi

gh_alert=""
if [ -n "$gh_indicator" ] && [ "$gh_indicator" != "none" ]; then
  parts=$(build_breakdown "$GH_COMP_CACHE" "  ")
  [ -n "$parts" ] && gh_alert="${parts} → https://www.githubstatus.com"
fi

# OpenAI: render in HEALTH_OPENAI_COMPONENTS order (cache order is undefined)
oai_alert=""
if [ -n "$oai_indicator" ] && [ "$oai_indicator" != "none" ] && [ -f "$OAI_COMP_CACHE" ]; then
  declare -A oai_status_map=()
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && oai_status_map["$k"]="$v"
  done < "$OAI_COMP_CACHE"
  # Map full names → short keys in the same order as the regex
  IFS='|' read -ra oai_full_order <<< "$HEALTH_OPENAI_COMPONENTS"
  parts=""
  for full in "${oai_full_order[@]}"; do
    case "$full" in
      Embeddings)   key="embed" ;;
      Fine-tuning)  key="ft" ;;
      Audio)        key="audio" ;;
      Images)       key="img" ;;
      Batch)        key="batch" ;;
      Moderations)  key="mod" ;;
      *)            key="$full" ;;
    esac
    status="${oai_status_map[$key]:-}"
    [ -z "$status" ] && continue
    icon=$(comp_icon "$status")
    if [ -z "$parts" ]; then parts="${icon}${key}"
    else parts="${parts}  ${icon}${key}"
    fi
  done
  [ -n "$parts" ] && oai_alert="${parts} → https://status.openai.com"
fi

cf_alert=""
if [ -n "$cf_indicator" ] && [ "$cf_indicator" != "none" ]; then
  parts=$(build_breakdown "$CF_COMP_CACHE" "  ")
  [ -n "$parts" ] && cf_alert="${parts} → https://www.cloudflarestatus.com"
fi

# ----- Background fetch: monthly cost (admin APIs) -----
if [ "$COST_ENABLED" = "1" ] && { [ -n "${ANTHROPIC_ADMIN_API_KEY:-}" ] || [ -n "${OPENAI_ADMIN_API_KEY:-}" ]; }; then
  age=$(cache_age "$COST_CACHE")
  if [ ! -f "$COST_CACHE" ] || [ "$age" -gt "$COST_TTL" ]; then
    (
      # Cost cache contains monthly $ totals — restrict to user-only perms
      umask 077
      month_start=$(date -u '+%Y-%m-01T00:00:00Z')
      now_iso=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
      month_start_epoch=$(date -u -d "$month_start" '+%s' 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$month_start" '+%s' 2>/dev/null)
      now_epoch=$(date -u '+%s')

      # Seed with previous values so a transient failure doesn't blank the display
      ant_total=""
      oai_total=""
      if [ -f "$COST_CACHE" ]; then
        prev_ant=$(awk -F'\t' '$1=="ant"{print $2}' "$COST_CACHE" 2>/dev/null)
        prev_oai=$(awk -F'\t' '$1=="oai"{print $2}' "$COST_CACHE" 2>/dev/null)
        [ -n "$prev_ant" ] && ant_total="$prev_ant"
        [ -n "$prev_oai" ] && oai_total="$prev_oai"
      fi

      if [ -n "${ANTHROPIC_ADMIN_API_KEY:-}" ]; then
        ant_json=$(curl -fsS --max-time 5 -G \
          "https://api.anthropic.com/v1/organizations/cost_report" \
          --data-urlencode "starting_at=${month_start}" \
          --data-urlencode "ending_at=${now_iso}" \
          --data-urlencode "bucket_width=1d" \
          -H "x-api-key: ${ANTHROPIC_ADMIN_API_KEY}" \
          -H "anthropic-version: 2023-06-01" 2>/dev/null)
        if [ -n "$ant_json" ]; then
          v=$(echo "$ant_json" | jq -r '[.data[]?.results[]?.amount | tonumber? // 0] | add // 0' 2>/dev/null)
          [ -n "$v" ] && ant_total="$v"
        fi
      fi

      if [ -n "${OPENAI_ADMIN_API_KEY:-}" ]; then
        oai_json=$(curl -fsS --max-time 5 -G \
          "https://api.openai.com/v1/organization/costs" \
          --data-urlencode "start_time=${month_start_epoch}" \
          --data-urlencode "end_time=${now_epoch}" \
          --data-urlencode "bucket_width=1d" \
          -H "Authorization: Bearer ${OPENAI_ADMIN_API_KEY}" 2>/dev/null)
        if [ -n "$oai_json" ]; then
          v=$(echo "$oai_json" | jq -r '[.data[]?.results[]?.amount.value // 0] | add // 0' 2>/dev/null)
          [ -n "$v" ] && oai_total="$v"
        fi
      fi

      printf "ant\t%s\noai\t%s\n" "$ant_total" "$oai_total" \
        > "${COST_CACHE}.tmp" && mv "${COST_CACHE}.tmp" "$COST_CACHE"
    ) >/dev/null 2>&1 & disown
  fi
fi

# ----- Read cached cost; build cost prefix with env-var omission rule -----
fmt_cost_value() {
  case "$1" in
    ""|"-"|"null") return 1 ;;
    *) awk -v v="$1" 'BEGIN{printf "$%.2f", v}' ;;
  esac
}

cost_parts=()
if [ "$COST_ENABLED" = "1" ] && [ -n "${ANTHROPIC_ADMIN_API_KEY:-}" ] && [ -f "$COST_CACHE" ]; then
  v=$(awk -F'\t' '$1=="ant"{print $2}' "$COST_CACHE")
  d=$(fmt_cost_value "$v") && cost_parts+=("ant:${d}/M")
fi
if [ "$COST_ENABLED" = "1" ] && [ -n "${OPENAI_ADMIN_API_KEY:-}" ] && [ -f "$COST_CACHE" ]; then
  v=$(awk -F'\t' '$1=="oai"{print $2}' "$COST_CACHE")
  d=$(fmt_cost_value "$v") && cost_parts+=("oai:${d}/M")
fi

cost_part=""
if [ ${#cost_parts[@]} -gt 0 ]; then
  joined=""
  for c in "${cost_parts[@]}"; do
    if [ -z "$joined" ]; then joined="$c"
    else joined="${joined}${STATUSLINE_FIELD_SEP}${c}"
    fi
  done
  cost_part="💰 ${joined}"
fi

# ----- Background fetch: weather (wttr.in) -----
weather_part=""
if [ "$WEATHER_ENABLED" = "1" ]; then
  age=$(cache_age "$WEATHER_CACHE")
  if [ ! -f "$WEATHER_CACHE" ] || [ "$age" -gt "$WEATHER_TTL" ]; then
    (
      coord_path="${WEATHER_COORDS}"
      url="https://wttr.in/${coord_path}?format=%c|%t|%h|%w|%p|%P|%m|%S|%s&lang=${WEATHER_LANG}"
      curl -fsS --max-time 4 "$url" > "${WEATHER_CACHE}.tmp" 2>/dev/null \
        && mv "${WEATHER_CACHE}.tmp" "$WEATHER_CACHE"
    ) >/dev/null 2>&1 & disown
  fi
  if [ -f "$WEATHER_CACHE" ] && [ -s "$WEATHER_CACHE" ]; then
    IFS='|' read -r w_cond w_temp w_hum w_wind w_prec w_pres w_moon w_rise w_set \
      < <(tr -d '\n' < "$WEATHER_CACHE")
    w_cond="${w_cond## }"; w_cond="${w_cond%% }"
    w_temp="${w_temp## }"; w_temp="${w_temp%% }"
    w_hum="${w_hum## }";   w_hum="${w_hum%% }"
    w_wind="${w_wind## }"; w_wind="${w_wind%% }"
    w_prec="${w_prec## }"; w_prec="${w_prec%% }"
    w_pres="${w_pres## }"; w_pres="${w_pres%% }"
    w_moon="${w_moon## }"; w_moon="${w_moon%% }"
    w_rise="${w_rise## }"; w_rise="${w_rise%% }"
    w_set="${w_set## }";   w_set="${w_set%% }"
    w_rise="${w_rise%:*}"
    w_set="${w_set%:*}"
  fi
fi

# ----- Background fetch: weather forecast (j1 JSON) -----
# Provides today's min/max + tomorrow + day-after-tomorrow forecast.
# Parsed via jq (no python3 dependency).
forecast_part=""
today_minmax_part=""
if [ "$WEATHER_ENABLED" = "1" ] && [ "$WEATHER_FORECAST_ENABLED" = "1" ]; then
  age=$(cache_age "$WEATHER_FORECAST_CACHE")
  if [ ! -f "$WEATHER_FORECAST_CACHE" ] || [ "$age" -gt "$WEATHER_FORECAST_TTL" ]; then
    (
      coord_path="${WEATHER_COORDS}"
      url="https://wttr.in/${coord_path}?format=j1&lang=${WEATHER_LANG}"
      curl -fsS --max-time 5 "$url" 2>/dev/null \
        | jq -r '
          def emoji(c):
            if c == "113" then "☀️"
            elif c == "116" then "⛅"
            elif (c == "119" or c == "122") then "☁️"
            elif (c == "143" or c == "248" or c == "260") then "🌫"
            elif (c == "200" or c == "386" or c == "389" or c == "392" or c == "395") then "⛈"
            elif (c == "179" or c == "227" or c == "230" or c == "320" or c == "323" or c == "326" or c == "329" or c == "332" or c == "335" or c == "338" or c == "368" or c == "371" or c == "374" or c == "377") then "🌨"
            else "🌧"
            end;
          # weather[0]=today, [1]=tomorrow, [2]=day-after; hourly[4] ≈ noon
          def noon(d): (d.hourly[4].weatherCode // d.hourly[0].weatherCode // "0");
          def rain(d): (d.hourly[4].chanceofrain // d.hourly[0].chanceofrain // "0");
          [
            (.weather[0].mintempC // ""),
            (.weather[0].maxtempC // ""),
            (if (.weather|length) > 1 then emoji(noon(.weather[1])) else "" end),
            (.weather[1].mintempC // ""),
            (.weather[1].maxtempC // ""),
            (if (.weather|length) > 1 then rain(.weather[1]) else "" end),
            (if (.weather|length) > 2 then emoji(noon(.weather[2])) else "" end),
            (.weather[2].mintempC // ""),
            (.weather[2].maxtempC // ""),
            (if (.weather|length) > 2 then rain(.weather[2]) else "" end)
          ] | @tsv
        ' 2>/dev/null > "${WEATHER_FORECAST_CACHE}.tmp" \
        && [ -s "${WEATHER_FORECAST_CACHE}.tmp" ] \
        && mv "${WEATHER_FORECAST_CACHE}.tmp" "$WEATHER_FORECAST_CACHE"
    ) >/dev/null 2>&1 & disown
  fi
  if [ -f "$WEATHER_FORECAST_CACHE" ] && [ -s "$WEATHER_FORECAST_CACHE" ]; then
    IFS=$'\t' read -r f_today_min f_today_max \
                       f_tom_em f_tom_min f_tom_max f_tom_rain \
                       f_day_em f_day_min f_day_max f_day_rain \
      < <(tr -d '\n' < "$WEATHER_FORECAST_CACHE")
    if [ -n "$f_today_min" ] && [ -n "$f_today_max" ]; then
      today_minmax_part=" (↓${f_today_min}/↑${f_today_max}°C)"
    fi
    if [ "$STATUSLINE_LANG" = "ja" ]; then
      tom_label="明日"; day_label="明後日"
    else
      tom_label="Tomorrow "; day_label="Day-after "
    fi
    forecast_items=()
    # Format: "<emoji> <min>/<max>°C" — min/max (low/high) matches the today row's
    # "(↓min/↑max°C)" format, and the space after the emoji prevents it from
    # visually crowding the first digit in monospace terminals.
    [ -n "$f_tom_max" ] && forecast_items+=("${tom_label}${f_tom_em} ${f_tom_min}/${f_tom_max}°C ☔${f_tom_rain}%")
    [ -n "$f_day_max" ] && forecast_items+=("${day_label}${f_day_em} ${f_day_min}/${f_day_max}°C ☔${f_day_rain}%")
    if [ ${#forecast_items[@]} -gt 0 ]; then
      joined=""
      for p in "${forecast_items[@]}"; do
        if [ -z "$joined" ]; then joined="$p"
        else joined="${joined}${STATUSLINE_FIELD_SEP}${p}"
        fi
      done
      forecast_part="$joined"
    fi
  fi
fi

# Assemble the current-weather row (now with today min/max appended after temp)
if [ -n "${w_temp:-}" ]; then
  weather_part="${w_cond}${w_temp}${today_minmax_part}${STATUSLINE_FIELD_SEP}💧${w_hum}${STATUSLINE_FIELD_SEP}💨${w_wind}${STATUSLINE_FIELD_SEP}☔${w_prec}${STATUSLINE_FIELD_SEP}🧭${w_pres}${STATUSLINE_FIELD_SEP}${w_moon}${STATUSLINE_FIELD_SEP}🌅${w_rise}${STATUSLINE_FIELD_SEP}🌇${w_set}"
fi

# ----- Background fetch: Anthropic news -----
news_title=""
news_link=""
if [ "$NEWS_ENABLED" = "1" ] && command -v python3 >/dev/null 2>&1; then
  age=$(cache_age "$NEWS_CACHE")
  if [ ! -f "$NEWS_CACHE" ] || [ "$age" -gt "$NEWS_TTL" ]; then
    (
      NEWS_COUNT="$NEWS_COUNT" python3 - > "${NEWS_CACHE}.tmp" 2>/dev/null <<'PY' \
        && mv "${NEWS_CACHE}.tmp" "$NEWS_CACHE"
import os, urllib.request, re, html, datetime
N = int(os.environ.get("NEWS_COUNT", "5"))
url = "https://www.anthropic.com/news"
try:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    body = urllib.request.urlopen(req, timeout=4).read().decode("utf-8", "replace")
    matches = re.findall(r'<a[^>]*href="(/news/[^"#]+)"[^>]*>(.*?)</a>', body, re.S)
    date_re = re.compile(r'([A-Z][a-z]{2}) (\d{1,2}),? (\d{4})')
    items = {}
    for href, inner in matches:
        text = html.unescape(re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', inner))).strip()
        m = date_re.search(text)
        if not m:
            continue
        try:
            d = datetime.datetime.strptime(f"{m.group(1)} {m.group(2)} {m.group(3)}", "%b %d %Y").date()
        except ValueError:
            continue
        title = (text[:m.start()] + " " + text[m.end():]).strip()
        title = re.sub(r'^(Announcements|Product|Policy|Research|Societal Impacts|Company)\s+', '', title)
        title = re.sub(r'\s+(Announcements|Product|Policy|Research|Societal Impacts|Company)\s+', ' ', title, count=1)
        title = re.split(r'(?<=[.!?])\s', title, maxsplit=1)[0].strip()
        if href not in items or d > items[href][0]:
            items[href] = (d, title)
    sorted_items = sorted(items.items(), key=lambda kv: kv[1][0], reverse=True)[:N]
    for href, (d, title) in sorted_items:
        link = "https://www.anthropic.com" + href
        print(f"{title}\t{link}")
except Exception:
    pass
PY
    ) >/dev/null 2>&1 & disown
  fi
  if [ -f "$NEWS_CACHE" ] && [ -s "$NEWS_CACHE" ]; then
    total=$(wc -l < "$NEWS_CACHE" 2>/dev/null | tr -d ' ')
    total=${total:-0}
    if [ "$total" -gt 0 ] 2>/dev/null; then
      idx=$(cat "$NEWS_IDX_FILE" 2>/dev/null)
      [ -z "$idx" ] && idx=0
      if [ -f "$NEWS_IDX_FILE" ]; then
        cache_mtime=$(stat -c %Y "$NEWS_CACHE" 2>/dev/null || stat -f %m "$NEWS_CACHE" 2>/dev/null || echo 0)
        idx_mtime=$(stat -c %Y "$NEWS_IDX_FILE" 2>/dev/null || stat -f %m "$NEWS_IDX_FILE" 2>/dev/null || echo 0)
        [ "$cache_mtime" -gt "$idx_mtime" ] && idx=0
      fi
      pick=$(( idx % total + 1 ))
      line=$(sed -n "${pick}p" "$NEWS_CACHE")
      IFS=$'\t' read -r news_title news_link <<< "$line"
      echo $(( idx + 1 )) > "$NEWS_IDX_FILE"
      if [ ${#news_title} -gt "$NEWS_TITLE_MAX" ]; then
        cut=$(( NEWS_TITLE_MAX - 3 ))
        news_title="${news_title:0:$cut}..."
      fi
      if [ "$total" -gt 1 ]; then
        news_title="[${pick}/${total}] ${news_title}"
      fi
    fi
  fi
fi

# ----- Datetime line -----
if [ -n "$STATUSLINE_TZ" ]; then
  datetime_str=$(TZ="$STATUSLINE_TZ" date "+${STATUSLINE_DATETIME_FMT}")
else
  datetime_str=$(date "+${STATUSLINE_DATETIME_FMT}")
fi
if [ -n "$STATUSLINE_TZ_LABEL" ]; then
  datetime_part="🕐 ${datetime_str} ${STATUSLINE_TZ_LABEL}"
else
  datetime_part="🕐 ${datetime_str}"
fi

# ===================== ASSEMBLE OUTPUT =====================

# Line 1: identity:project (branch)
project_part=""
[ -n "$git_project" ] && project_part=$(printf ":\033[01;36m%s\033[00m" "$git_project")
branch_part=""
[ -n "$short_branch" ] && branch_part=$(printf " (\033[01;33m%s%s%s\033[00m)" "$short_branch" "$git_state" "$ci_segment")
line1=$(printf "\033[01;32m%s\033[00m%s%s" "$STATUSLINE_USER_HOST" "$project_part" "$branch_part")

# Line 2: model + ctx (with health prefixes)
model_line="${extra_health_prefix}${ant_prefix}${model_part}"
[ -n "$ctx_part" ] && model_line="${model_line}${STATUSLINE_FIELD_SEP}${ctx_part}"

lines=("$line1" "$model_line")

# ----- MINIMAL MODE SHORT-CIRCUIT -----
if [ "$mode" = "minimal" ]; then
  printf "%s" "$line1"
  printf "\n%s" "$model_line"
  if [ -n "$rate_part" ]; then
    printf "\n%s" "$rate_part"
    border=$(printf "%${STATUSLINE_BORDER_WIDTH}s" "" | sed "s/ /${STATUSLINE_BORDER_CHAR}/g")
    printf "\n%s" "$border"
  fi
  exit 0
fi

# Billing line: cost + rate-limits, joined with separator
billing_parts=()
[ -n "$cost_part" ] && billing_parts+=("$cost_part")
[ -n "$rate_part" ] && billing_parts+=("$rate_part")
if [ ${#billing_parts[@]} -gt 0 ]; then
  joined=""
  for p in "${billing_parts[@]}"; do
    if [ -z "$joined" ]; then joined="$p"
    else joined="${joined}${STATUSLINE_FIELD_SEP}${p}"
    fi
  done
  lines+=("$joined")
fi

# Datetime line (anchors the weather/forecast rows below it — keep them grouped)
lines+=("$datetime_part")

# Weather line
[ -n "$weather_part" ] && lines+=("$weather_part")

# Forecast line (today min/max is already inlined into weather row; this row
# carries tomorrow + day-after-tomorrow)
[ -n "$forecast_part" ] && lines+=("$forecast_part")

# Trailing block: border + news + service-health breakdowns (only if anything to show)
trailing=()
if [ -n "$news_title" ]; then
  trailing+=("📰${news_title}")
  [ -n "$news_link" ] && trailing+=("   🔗${news_link}")
fi
[ -n "$ant_alert" ]  && trailing+=("$ant_alert")
[ -n "$oai_alert" ]  && trailing+=("$oai_alert")
[ -n "$cf_alert" ]   && trailing+=("$cf_alert")
[ -n "$gh_alert" ]   && trailing+=("$gh_alert")

if [ ${#trailing[@]} -gt 0 ]; then
  border=$(printf "%${STATUSLINE_BORDER_WIDTH}s" "" | sed "s/ /${STATUSLINE_BORDER_CHAR}/g")
  lines+=("$border")
  for t in "${trailing[@]}"; do
    lines+=("$t")
  done
fi

# Print joined with newlines (no trailing newline)
first=1
for l in "${lines[@]}"; do
  if [ $first -eq 1 ]; then
    printf "%s" "$l"
    first=0
  else
    printf "\n%s" "$l"
  fi
done
