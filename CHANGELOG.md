# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

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

[0.1.0]: https://github.com/JFK/claude-statusline-builder-plugin/releases/tag/v0.1.0
