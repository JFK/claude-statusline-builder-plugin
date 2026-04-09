# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-04-09

Local awareness — the statusline now reflects what's happening inside
your repo and inside your Claude Code session, without reaching out to
any new external systems.

### Added
- **Git working-tree state on line 1.** The branch parens now append
  `●N` (modified/untracked), `±N` (staged), `↑N` (ahead), `↓N` (behind)
  whenever any of them are non-zero, so you notice uncommitted or
  unpushed work mid-session without running `git status`. Clean repos
  still render as `(branch)` with no visual change. New
  `GIT_DIRTY_ENABLED` env var (default `1`) lets users opt out.
  Runs in ~6ms on typical repos. (#1)
- **Context-window burn rate on the model line.** `ctx:234.0k/1.0M(23%)`
  becomes `ctx:234.0k/1.0M(23% +12.4k/turn)` when the window is growing
  steadily, so users can judge when to `/clear` before hitting the
  ceiling. Per-session sliding window of the last
  `CTX_BURN_WINDOW` samples (default 5), with
  `CTX_BURN_MIN_DELTA` (default 1000 tokens) noise floor. Suppressed
  cleanly after `/clear` (negative delta) and on the first render of a
  new session (insufficient samples). Multi-session safe via
  session-id keyed slices. (#3)

### Fixed
- **ctx-history cache is now user-only (0600).** The per-session cache
  that powers the burn rate was writing at the default 0644 umask,
  leaving session ids and per-turn token counts readable by other local
  users on multi-user systems. The persist block is now wrapped in a
  `( umask 077; ... )` subshell so the cache lands at 0600; existing
  0644 files flip automatically on the next render (`mv` preserves the
  temp file's mode). Matches the existing convention for the cost
  cache. Found in the CSO security review of the burn-rate feature.

## [0.1.4] - 2026-04-09

### Fixed
- **Clock row renders with a space after the 🕐 emoji** (`🕐 2026-04-09`
  instead of `🕐2026-04-09`), matching the spacing convention already
  used by the forecast row. The datetime section was the last
  emoji-prefixed line that still collided visually with its value.
  (#5)

## [0.1.3] - 2026-04-08

### Added
- **Minimal mode now surfaces the rate-limit row** (`5h:… 7d:…`) with a
  trailing border, so the compact render still shows when your 5h / 7d
  usage window resets

### Changed
- **Identity prefix is now context-aware.** When `$USER` and
  `$(hostname -s)` match (common on personal machines), the `user@host`
  prefix collapses to just `$USER` inside a git repo (the project name
  on line 1 provides the context) and falls back to `$USER@<pwd name>`
  outside a git repo (so the current directory still anchors the line).
  Users with distinct user/host names see no change.
- **`STATUSLINE_TZ_LABEL` is now auto-detected** from `date +%Z` (e.g.
  `JST`, `PST`, `CET`) when unset, so the clock and reset rows carry a
  timezone suffix without per-user config. Explicitly setting the var
  to `""` suppresses the suffix.
- **Detail mode reorders the 🕐 clock row above weather/forecast** so
  the datetime anchors the weather block rather than trailing after it

### Fixed
- Removed now-unused `cur_input` / `cur_output` / `cur_cache_r` captures
  from the jq parse — leftover from the v0.1.2 `sess:` field removal

## [0.1.2] - 2026-04-08

### Removed
- **`sess:` field** on the model line (`ctx:234.0k/1.0M(23%)  sess:103.4k`
  → `ctx:234.0k/1.0M(23%)`). The value — `input_tokens + output_tokens +
  cache_read_input_tokens` — was within ~1k of rounding noise of `ctx:` in
  every normal session, because Claude's prefix caching routes system
  prompt / tools / past turns through `cache_read_input_tokens`. Two fields
  showing the same number added visual noise without information. The
  model line is now one field shorter and fits more easily on narrow
  terminals.

## [0.1.1] - 2026-04-08

### Added
- **Today's min/max temperature** appended inline to the current weather
  row (e.g. `☀️ +18°C (↓9/↑17°C)`)
- **Tomorrow + day-after-tomorrow forecast row** rendered between the
  current weather row and the datetime row, with weather emoji + max/min
  temp + chance-of-rain (e.g. `Tomorrow ☀️18/12°C ☔0%  Day-after 🌧19/15°C ☔61%`)
- Forecast row labels switch to 明日 / 明後日 when `STATUSLINE_LANG=ja`
- New env vars: `WEATHER_FORECAST_ENABLED` (default `1`), `WEATHER_FORECAST_TTL`
  (default `10800` — 3 hours)
- New cache file: `${STATUSLINE_CACHE_DIR}/claude-statusline-weather-forecast`
  (TSV, populated by a second wttr.in fetch using `format=j1`, parsed via jq)

### Changed
- Replaced the `eval`-based weather field trim loop with explicit per-variable
  trims (cleaner, also closes a Low-severity CSO finding from v0.1.0 review)

## [0.1.0] - 2026-04-08

### Added
- Initial release of `claude-statusline-builder`
- Bash statusline script (`scripts/statusline-command.sh`) with TTL-cached background fetches for weather (wttr.in), Anthropic news, monthly cost (Anthropic + OpenAI admin APIs), and service health (Anthropic, GitHub, OpenAI, Cloudflare via Statuspage)
- Configurable defaults block at the top of the script — every locale / weather / news / health / cost / rendering value can be overridden via `~/.claude/statusline-config.sh`
- Six commands:
  - `/install` — copies the script to `~/.claude/`, backs up existing files, wires `settings.json`
  - `/toggle` — flips between minimal and detail rendering modes via a flag file
  - `/preview` — renders the statusline once with a synthetic fixture
  - `/doctor` — 12-point diagnostic checklist with optional `fix` hints
  - `/config` — shows effective values, generates a fresh template, or prints one variable
  - `/uninstall` — restores the previous `settings.json` and removes installed files
- One subagent: `statusline-builder` — interactive 4–8 question config wizard
- Cost-omission rule: when an admin API key is unset, that provider's cost slot is omitted entirely (not displayed as `—`); if both are unset, the cost prefix vanishes from the billing line
- Back-compat alias for the `ANTHOROPIC_ADMIN_API_KEY` typo as `ANTHROPIC_ADMIN_API_KEY`
- Minimal-mode short-circuit: skips weather / news / health / cost / datetime / border for sub-30ms render
- Documentation: README (en/ja), SECURITY, CONTRIBUTING, CHANGELOG, LICENSE
- Shellcheck CI workflow

[0.1.3]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.3
[0.1.2]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.2
[0.1.1]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.1
[0.1.0]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.0
