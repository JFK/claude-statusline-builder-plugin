---
description: Diagnose why the statusline isn't rendering correctly — checks deps, env vars, settings.json wiring, cache files, and HTTPS reachability
arguments:
  - name: input
    description: "Optional: 'verbose' for full per-component output, 'fix' to suggest commands the user can run."
    required: false
---

## Trust boundary

Diagnostic output must NEVER include the value of any environment variable that matches `*_API_KEY` or `*_TOKEN`. Show only "set" / "unset" — never the secret itself.

## Steps

Run a structured 13-point checklist. For each step, print one line: `✅` (pass), `⚠️` (warn), or `❌` (fail), followed by a short label and the result.

### 1. Required dependencies on PATH
`command -v jq curl bash awk git python3` — `python3` is optional (only needed for news scraping); the rest are required.

### 2. Statusline script installed and executable
`test -x "$HOME/.claude/statusline-command.sh"` — if missing, suggest `/claude-statusline-builder:install`.

### 3. settings.json wired
`jq -e '.statusLine.command | test("statusline-command.sh")' "$HOME/.claude/settings.json"` — if false, suggest `/claude-statusline-builder:install`.

### 4. Cache directory exists and is writable
`test -d "$HOME/.claude/cache" -a -w "$HOME/.claude/cache"`. Also check the script's `STATUSLINE_CACHE_DIR` (defaults to `/tmp`) is writable.

### 5. Current mode
Report whether `~/.claude/cache/statusline-minimal` exists. State: minimal | detail.

### 6. User config present
`test -f "$HOME/.claude/statusline-config.sh"`. If absent, the script uses defaults — that's fine, but note it.

### 7. Admin API keys present (without echoing values)
Check whether `ANTHROPIC_ADMIN_API_KEY` (or its `ANTHOROPIC_ADMIN_API_KEY` typo alias) is exported in the environment that the statusline runs under. Same for `OPENAI_ADMIN_API_KEY`. Print only "set" or "unset". If both unset, note that the cost line will be omitted entirely (this is intentional, not a bug).

### 8. Cache file freshness
For each of `weather`, `anthropic-news`, `monthly-cost`, and the four `*-health` caches, report: present? age in seconds? stale (older than the relevant TTL)? Use `stat -c %Y` (Linux) with `stat -f %m` (BSD/macOS) fallback.

### 9. Outbound HTTPS reachability
`curl -fsS --max-time 4 https://wttr.in/?format=3 >/dev/null` — if this fails, all background fetches are blocked. Suggest checking firewall/proxy.

### 10. Weather location sanity
Read `WEATHER_COORDS` from the shell environment that sources `~/.claude/statusline-config.sh` (source the file in a subshell, then `echo "${WEATHER_COORDS:-}"`). Also probe what wttr.in currently resolves the client IP to:

```bash
wttr_ip_loc=$(curl -fsS --max-time 4 https://wttr.in/?format=%l 2>/dev/null)
```

Report one of three states:
- **override set** → `✅ weather location: override "$WEATHER_COORDS" (wttr-IP would pick "$wttr_ip_loc")`
- **override unset, probe succeeded** → `⚠️ weather location: auto-detect → "$wttr_ip_loc". Verify this matches where you actually are; egress IPs on WSL2/VPN/cloud-shell often resolve to a datacenter city. Set WEATHER_COORDS in ~/.claude/statusline-config.sh to override.`
- **override unset, probe failed** → `⚠️ weather location: auto-detect but wttr.in unreachable (see step 9)`

Never try to infer "correct" — doctor has no way to know where the user physically is. Just surface the two values so the user can cross-check.

### 11. One Statuspage probe
`curl -fsS --max-time 4 https://status.claude.com/api/v2/summary.json | jq -r .status.indicator` — if this returns a value (`none`, `minor`, etc.), Statuspage is reachable.

### 12. End-to-end render
Pipe `${CLAUDE_PLUGIN_ROOT}/scripts/preview-fixture.json` into the installed script and check the exit code is 0. If non-zero, show stderr.

### 13. Date portability
`date -d @1700000000 +%H:%M 2>/dev/null` (GNU) or `date -r 1700000000 +%H:%M 2>/dev/null` (BSD) — confirm at least one works. The script tries both.

## Output

Group results into:
- **Required** (steps 1–3, 12) — any ❌ here means the statusline won't render at all
- **Recommended** (steps 4–6, 13) — any ❌ here means partial functionality
- **Network / freshness** (steps 7–11) — any ❌ here means rows that depend on external data may be missing or stale

End with a one-line summary: "All checks passed." or "X check(s) failed — see above."

If `$ARGUMENTS` is `fix`, after each ❌ append a one-line "try this" hint (e.g. `try: sudo apt install jq`). Never auto-remediate.

Doctor must NEVER:
- Modify `~/.claude/settings.json`, the statusline script, or any config file
- Echo admin API keys or any secret values
- Run package managers

---

> ⚠️ **AI-generated diagnosis**: Doctor reports current state but does not change anything. Use `/claude-statusline-builder:install` or `/claude-statusline-builder:uninstall` to make changes.
