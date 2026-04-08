# claude-statusline-builder

A rich, configurable status line for [Claude Code](https://claude.com/claude-code) — model + context window + rate limits + monthly Anthropic/OpenAI cost + weather + service health (Anthropic / GitHub / OpenAI / Cloudflare) + Anthropic news headlines, with a one-key minimal/detail toggle.

All external HTTP fetches are TTL-cached and run in the background, so the foreground render stays fast on every Claude turn.

```
jfk@laptop:demo-project (main)
🟢gh 🟢cf 🟢oai 🟢Claude Opus 4.6 (1M context)  ctx:234.0k/1.0M(23%)  sess:103.4k
💰 ant:$12.34/M  oai:$3.21/M  5h:41% → 14:00 PST  7d:17% → Fri 14:00 PST
☀️ +18°C  💧19%  💨↑15km/h  ☔0.0mm  🧭1017hPa  🌗  🌅05:18  🌇18:07
🕐2026-04-08 (Wed) 14:05
────────────────────────────────────────────────────────────
📰[1/5] Anthropic expands partnership with Google and Broadcom
   🔗https://www.anthropic.com/news/google-broadcom-partnership-compute
```

## 60-second quickstart

```
/plugin marketplace add JFK/claude-statusline-builder-plugin
/plugin install claude-statusline-builder
/claude-statusline-builder:install
/claude-statusline-builder:preview
```

That's it. The statusline will appear on the next Claude Code turn. To toggle between minimal and detail rendering at any time:

```
/claude-statusline-builder:toggle
```

For guided setup (timezone, weather, providers, cost tracking), spawn the builder agent — Claude Code will offer it automatically when its description matches, or you can ask: "use the statusline-builder agent to configure my statusline".

## Commands

| Command | What it does |
|---|---|
| `/claude-statusline-builder:install` | Copies the script to `~/.claude/statusline-command.sh`, backs up any existing one, wires it into `~/.claude/settings.json`, and stamps a commented config template |
| `/claude-statusline-builder:toggle` | Flips between **minimal** (identity + branch + model) and **detail** (full multi-line) rendering. Pass `minimal`, `detail`, `status`, or no argument to flip |
| `/claude-statusline-builder:preview` | Renders the statusline once with a synthetic JSON fixture so you can verify it without waiting for a Claude turn. Pass `minimal` or `detail` for a one-shot mode override |
| `/claude-statusline-builder:doctor` | 12-point diagnosis: deps, settings.json wiring, cache freshness, env vars, HTTPS reachability, fixture render, date portability. Pass `fix` for one-line remediation hints |
| `/claude-statusline-builder:config` | `show` (default) prints all effective values with origin (user vs default). `init` stamps a fresh config template. `<KEY_NAME>` prints one value |
| `/claude-statusline-builder:uninstall` | Restores the previous `~/.claude/settings.json` from backup, deletes the installed script and the mode flag. Pass `purge` to also remove your config and `/tmp` cache files |

## The builder agent

Subagent: `claude-statusline-builder:statusline-builder`

An interactive 4–8 question wizard that walks you through your locale, weather, language, service health providers, cost tracking, and rendering preferences, then writes `~/.claude/statusline-config.sh` for you and verifies by rendering the fixture. Use this when you want guided setup instead of editing the bash config by hand.

The agent never asks you to type admin API keys into chat — those must be set in `~/.profile` (or anywhere `bash` will source them) before running the wizard.

## Configuration

Your overrides live in `~/.claude/statusline-config.sh` (sourced by the script on every render). The plugin's `scripts/statusline-config.sample.sh` is the canonical template — `/install` and `/config init` stamp it out for you.

### All overridable variables

| Variable | Default | Notes |
|---|---|---|
| `STATUSLINE_TZ` | *(system)* | IANA timezone, e.g. `Asia/Tokyo` |
| `STATUSLINE_TZ_LABEL` | *(empty)* | Suffix on reset times, e.g. `JST` |
| `STATUSLINE_LANG` | `en` | `ja` enables 月火水木金土日 day-of-week mapping for the 7d reset |
| `STATUSLINE_DATETIME_FMT` | `%Y-%m-%d (%a) %H:%M` | strftime format for the datetime row |
| `STATUSLINE_USER_HOST` | `$USER@$(hostname -s)` | Identity prefix on line 1 |
| `WEATHER_ENABLED` | `1` | `0` disables the weather row |
| `WEATHER_COORDS` | *(empty)* | `lat,lon`. Empty = wttr.in IP-detect |
| `WEATHER_LANG` | `en` | wttr.in language code |
| `WEATHER_TTL` | `1800` | Seconds |
| `WEATHER_FORECAST_ENABLED` | `1` | `0` drops the inline today min/max **and** the tomorrow + day-after forecast row |
| `WEATHER_FORECAST_TTL` | `10800` | Seconds. Forecasts change slowly — 3h cache |
| `NEWS_ENABLED` | `1` | `0` disables Anthropic news rotation. Requires `python3` |
| `NEWS_COUNT` | `5` | Cache N items, rotate one per render |
| `NEWS_TITLE_MAX` | `72` | Truncate titles longer than N chars |
| `NEWS_TTL` | `3600` | Seconds |
| `HEALTH_ENABLED` | `1` | `0` disables all four service-health rows |
| `HEALTH_TTL` | `300` | Seconds |
| `HEALTH_PROVIDERS` | `anthropic github openai cloudflare` | Space-separated list. Drop providers you don't care about |
| `HEALTH_CLOUDFLARE_REGION_FILTER` | *(empty)* | Regex over IATA codes, e.g. `NRT\|KIX\|FUK\|OKA` for Japanese PoPs |
| `HEALTH_OPENAI_COMPONENTS` | `Embeddings\|Fine-tuning\|Audio\|Images\|Batch\|Moderations` | Regex over full component names |
| `COST_ENABLED` | `1` | `0` disables both monthly cost slots |
| `COST_TTL` | `3600` | Seconds |
| `STATUSLINE_BORDER_CHAR` | `─` | U+2500. Use `-` on legacy terminals |
| `STATUSLINE_BORDER_WIDTH` | `60` | Repeat count |
| `STATUSLINE_FIELD_SEP` | `  ` (two spaces) | Between fields on a row |
| `STATUSLINE_PCT_YELLOW` | `50` | Color ramp threshold |
| `STATUSLINE_PCT_MAGENTA` | `75` | Color ramp threshold |
| `STATUSLINE_PCT_RED` | `90` | Color ramp threshold (bold red) |
| `STATUSLINE_CACHE_DIR` | `/tmp` | Where TTL'd cache files live |

### Admin API keys (optional)

The monthly cost slots require admin-scoped API keys for the providers you want to track. Set them in `~/.profile`:

```bash
export ANTHROPIC_ADMIN_API_KEY="sk-ant-admin-..."   # console.anthropic.com → Admin API
export OPENAI_ADMIN_API_KEY="sk-admin-..."           # platform.openai.com → API Keys → Admin
```

**Cost-omission rule:** if a key is unset, that provider's slot is omitted entirely (not displayed as `—`). If both are unset, no `💰` prefix appears at all — only the rate limits will render on the billing line.

The script also accepts `ANTHOROPIC_ADMIN_API_KEY` (with the typo) as a back-compat alias for users who have it spelled that way in older shell configs.

## How it stays fast

- **One foreground jq call** parses the statusline JSON; everything else is bash builtins
- **All HTTP fetches happen in `( ... ) & disown` background subshells** with `--max-time 4` and atomic `tmp → mv` cache writes
- **Cold start** populates caches in 5–10 seconds; **warm renders** read pre-fetched files
- **Minimal mode** short-circuits before any background fetch logic — sub-30ms even on cold start

## Supported platforms

- **Linux** (tested on Ubuntu, Debian, Arch, Alpine)
- **macOS** (uses BSD `date -r` fallback when GNU `date -d` is unavailable)
- **WSL2** (the supported path on Windows — native cmd/PowerShell is not supported)

## Troubleshooting

Run `/claude-statusline-builder:doctor` first. It surfaces the most common issues (missing `jq`/`curl`, settings.json not wired, stale caches, blocked HTTPS) with one-line hints. `doctor fix` adds remediation suggestions.

If the statusline renders but a row is missing:
- **No weather** → check `WEATHER_ENABLED=1` and that `wttr.in` is reachable
- **No news** → requires `python3` on PATH; `python3 --version` should work
- **No cost** → admin key for that provider is unset (this is intentional, not a bug)
- **No service health** → check `HEALTH_PROVIDERS` includes the provider, and outbound HTTPS to `*.statuspage.io` mirrors

## Security

See [SECURITY.md](SECURITY.md) for the full threat model. Highlights:

- The script reads admin API keys from your environment but **never echoes them to stdout, stderr, or chat output**
- All cache files in `/tmp` contain only public health/weather/news data plus numeric monthly cost totals — nothing sensitive
- No telemetry. The script never phones home

## Related plugins

This is part of an ecosystem of MIT-licensed Claude Code plugins by [@JFK](https://github.com/JFK):

- [claude-c-suite-plugin](https://github.com/JFK/claude-c-suite-plugin) — CEO/CTO/CSO/PM review skills
- [claude-phd-panel-plugin](https://github.com/JFK/claude-phd-panel-plugin) — academic review skills (CS, DB, Stats, ...)
- [expert-craft-plugin](https://github.com/JFK/expert-craft-plugin) — hire and retire custom expert review skills

## License

[MIT](LICENSE) © Fumikazu Kiyota
