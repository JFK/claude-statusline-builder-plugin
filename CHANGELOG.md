# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

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

[0.1.1]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.1
[0.1.0]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.0
