# Contributing

Thanks for considering a contribution! This is a small, focused plugin and the bar for changes is "does it make the statusline more useful for more people without making it slower or more complex".

## Development

There is no build step. The plugin is pure bash + markdown.

```bash
git clone https://github.com/JFK/claude-statusline-builder-plugin.git
cd claude-statusline-builder-plugin

# Render with the fixture
cat scripts/preview-fixture.json | bash scripts/statusline-command.sh

# Render in minimal mode
CLAUDE_STATUSLINE_FORCE_MODE=minimal bash scripts/statusline-command.sh < scripts/preview-fixture.json

# Lint
shellcheck scripts/statusline-command.sh scripts/statusline-config.sample.sh
```

## Before opening a PR

Please verify all of the following pass:

```bash
# 1. Plugin metadata is valid JSON
jq -e . .claude-plugin/plugin.json
jq -e . .claude-plugin/marketplace.json

# 2. Versions sync between plugin.json and marketplace.json
test "$(jq -r .version .claude-plugin/plugin.json)" \
   = "$(jq -r .plugins[0].version .claude-plugin/marketplace.json)"

# 3. Shellcheck passes
shellcheck scripts/statusline-command.sh scripts/statusline-config.sample.sh

# 4. Script renders the fixture cleanly
bash scripts/statusline-command.sh < scripts/preview-fixture.json

# 5. Minimal-mode short-circuit works
CLAUDE_STATUSLINE_FORCE_MODE=minimal bash scripts/statusline-command.sh < scripts/preview-fixture.json

# 6. Cost-omission rule still holds
( unset ANTHROPIC_ADMIN_API_KEY ANTHOROPIC_ADMIN_API_KEY OPENAI_ADMIN_API_KEY
  bash scripts/statusline-command.sh < scripts/preview-fixture.json | grep -E '(ant:|oai:)' && echo FAIL || echo PASS )
```

CI runs items 1–6 on every push and PR via `.github/workflows/shellcheck.yml`.

## Style

- **Pure bash.** No Python, Node, Rust, or anything else on the hot path. The news scraper uses `python3` because it ships with most distros, but it's a background-only optional component
- **Hot-path discipline.** Every change must keep the foreground render fast. If a change adds work, it must happen in `( ... ) & disown` background subshells with file caches
- **Configurability before features.** A new feature should be opt-in via an env var with a publish-friendly default (off, or empty, or "auto-detect"). Don't bake personal preferences into defaults
- **Never echo secrets.** Admin API keys must never appear in stdout, stderr, chat output, or `/tmp` cache files. The bound for any new code that touches keys is "could a screencast accidentally show this?"
- **Don't add modules.** The script is monolithic on purpose. If you find yourself wanting to `source` a helper file, the function probably belongs inline at its call site
- **Document the variable.** Any new env var must be added to (a) the CONFIG block in `scripts/statusline-command.sh`, (b) `scripts/statusline-config.sample.sh`, (c) the README's variable table

## Adding a new external data source

Follow the existing pattern (weather, news, health, cost):

1. Define `*_ENABLED`, `*_TTL`, and any source-specific config in the CONFIG block
2. Add a background fetch block with `( curl ... > ${CACHE}.tmp && mv ${CACHE}.tmp ${CACHE} ) & disown 2>/dev/null` and a `cache_age` TTL check
3. Add a foreground reader that builds a display part from the cache file (gracefully handling absent/empty)
4. Add the part to the assembly section, gated by minimal-mode short-circuit
5. Document the new variables in README + SECURITY (endpoints) + sample config
6. Add a test to the verification list

## Versioning

Semver. Bump:

- **Patch** (0.1.x): bug fixes, doc updates, internal refactors
- **Minor** (0.x.0): new commands, new env vars, new data sources
- **Major** (x.0.0): renamed env vars, removed commands, breaking changes to config file format

Always update both `plugin.json` and `marketplace.json` versions in the same commit.

## Reporting bugs

Open an issue with:

- The output of `/claude-statusline-builder:doctor`
- Your OS + bash version (`bash --version`)
- The contents of `~/.claude/statusline-config.sh` with any secrets redacted
- A copy-paste of the rendered statusline (or a screenshot if ANSI rendering is the issue)

For security issues, see [SECURITY.md](SECURITY.md).
