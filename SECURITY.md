# Security policy

## Threat model

`claude-statusline-builder` is a bash script that runs **on every Claude Code turn** with whatever environment variables are present in your shell. It reads two admin API keys, performs background HTTPS requests to public Statuspage / wttr.in / news endpoints, and caches the results in `/tmp`. There is no remote control surface, no telemetry, and no input from the chat conversation that influences the script's behavior at runtime.

## Outbound endpoints

The script makes background `curl` requests (with `--max-time 4`, `-fsS`) to:

| Endpoint | Purpose | Auth |
|---|---|---|
| `https://wttr.in/...` | Weather | None |
| `https://www.anthropic.com/news` | News headlines (scraped via Python) | None |
| `https://status.claude.com/api/v2/summary.json` | Anthropic service health | None |
| `https://www.githubstatus.com/api/v2/summary.json` | GitHub service health | None |
| `https://status.openai.com/api/v2/summary.json` | OpenAI service health | None |
| `https://www.cloudflarestatus.com/api/v2/summary.json` | Cloudflare service health | None |
| `https://api.anthropic.com/v1/organizations/cost_report` | Monthly Anthropic cost | `x-api-key: $ANTHROPIC_ADMIN_API_KEY` |
| `https://api.openai.com/v1/organization/costs` | Monthly OpenAI cost | `Authorization: Bearer $OPENAI_ADMIN_API_KEY` |

All endpoints can be selectively disabled via `WEATHER_ENABLED=0`, `NEWS_ENABLED=0`, `HEALTH_ENABLED=0`, `COST_ENABLED=0`, or by removing providers from `HEALTH_PROVIDERS`.

## Admin API key handling

- Keys are read from environment variables: `ANTHROPIC_ADMIN_API_KEY` and `OPENAI_ADMIN_API_KEY` (with `ANTHOROPIC_ADMIN_API_KEY` accepted as a back-compat alias for the typo'd spelling)
- Keys are passed to `curl` via `-H "x-api-key: ..."` and `-H "Authorization: Bearer ..."` only
- Keys are **never written to stdout, stderr, chat output, log files, or the `/tmp` cache**. The cost cache contains only numeric monthly totals
- The included slash commands and the `statusline-builder` agent are bound by their command/agent body to never echo key values; they only ever report "set" or "unset"
- Recommended location: `~/.profile` (sourced by `bash` on login). Anything that produces an exported environment variable in the shell that runs the statusline command works

If a key is unset, that provider's cost slot is omitted from the billing line entirely (not displayed as `—`). This is intentional: it makes the empty state visually distinct from a "fetched but zero" state.

## Cache file contents

All cache files live under `STATUSLINE_CACHE_DIR` (default `/tmp`) and contain only:

- Public weather strings from `wttr.in`
- Public news headlines + URLs from `anthropic.com/news`
- Public service-health indicators from Statuspage
- Numeric monthly cost totals (no per-request data, no model names, no token counts)

Cache files are written atomically via `mktemp + mv`. They are world-readable on multi-user systems unless you set `STATUSLINE_CACHE_DIR` to a private directory.

## Trust boundary

The script does **not** read any data from the Claude Code conversation other than the standard JSON payload Claude Code passes on stdin (model id, context window, rate limits, cwd). It does **not** parse or execute anything from cache files as code. The only code path that involves an external HTML/JSON parser is the news scraper, which uses `python3` with `urllib.request` against a single hardcoded URL and feeds the result through `re` and `html` standard-library modules — no `eval`, no shell execution.

## Telemetry

There is none. The script never phones home. It does not collect usage statistics, error reports, or any user-identifiable data. The only outbound traffic is the HTTPS requests listed above, which return public data (with the exception of your own organization's cost totals, which only your admin keys can fetch).

## Reporting a vulnerability

If you find a security issue, please:

1. **Do not** open a public GitHub issue
2. Email the maintainer: `fumikazu.kiyota@gmail.com` with `[claude-statusline-builder security]` in the subject
3. Include: affected version, reproduction steps, expected vs observed behavior, and your assessment of severity

We aim to acknowledge reports within 7 days and to ship a fix within 30 days for high-severity issues.

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x | ✅ |

Older versions will not receive security updates. Always run the latest minor release.
