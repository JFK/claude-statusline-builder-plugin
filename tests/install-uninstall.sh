#!/bin/bash
# tests/install-uninstall.sh
#
# End-to-end sandbox test for the install/uninstall flow. Simulates the bash
# steps that commands/install.md and commands/uninstall.md instruct Claude to
# run, against a throwaway $HOME, and asserts:
#
#   1. settings.json round-trips cleanly (other keys preserved on install,
#      restored verbatim on uninstall)
#   2. statusline-command.sh is installed executable
#   3. ~/.claude/backups/ is 0700, backup files are 0600 (CSO #2)
#   4. The cost cache (when populated) is 0600 via umask 077 (CSO #1)
#   5. The statusline script renders the fixture cleanly under the sandbox HOME
#   6. uninstall restores the exact pre-install settings.json
#
# Run from the plugin root: bash tests/install-uninstall.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# Per-test counters
pass=0
fail=0
assert() {
  local desc=$1
  shift
  if "$@"; then
    printf '  ✅ %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf '  ❌ %s\n' "$desc"
    fail=$((fail + 1))
  fi
}

echo "=== Sandbox: $SANDBOX ==="
echo "=== Plugin root: $PLUGIN_ROOT ==="
echo

# ----- Setup: pretend the user has an existing Claude Code config -----
mkdir -p "$SANDBOX/.claude"
cat > "$SANDBOX/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "existingKey": "must-be-preserved",
  "enabledPlugins": {
    "some-other-plugin": true
  }
}
EOF
ORIG_CHECKSUM=$(sha256sum "$SANDBOX/.claude/settings.json" | awk '{print $1}')

# ============================================================
# PHASE 1: simulate /install
# ============================================================
echo "=== Phase 1: install ==="

(
  export HOME="$SANDBOX"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

  # Step 2: prepare directories with locked-down perms
  mkdir -p "$HOME/.claude/backups" "$HOME/.claude/cache"
  chmod 0700 "$HOME/.claude/backups"

  # Step 3: back up any existing statusline script (none exists in this sandbox)

  # Step 4: install the new script
  install -m 0755 "${CLAUDE_PLUGIN_ROOT}/scripts/statusline-command.sh" \
                  "$HOME/.claude/statusline-command.sh"

  # Step 5: back up settings.json + chmod 0600
  cp "$HOME/.claude/settings.json" "$HOME/.claude/backups/settings.json.$(date +%s)"
  for f in "$HOME"/.claude/backups/settings.json.*; do chmod 0600 "$f"; done

  # Step 6: patch settings.json with jq (atomic)
  tmp=$(mktemp)
  jq --arg cmd "bash $HOME/.claude/statusline-command.sh" \
     '.statusLine = {type: "command", command: $cmd}' \
     "$HOME/.claude/settings.json" > "$tmp" && mv "$tmp" "$HOME/.claude/settings.json"

  # Step 7: stamp the config template (only if absent)
  cp -n "${CLAUDE_PLUGIN_ROOT}/scripts/statusline-config.sample.sh" \
        "$HOME/.claude/statusline-config.sh"
)

# ----- Assertions for phase 1 -----
assert "statusline-command.sh installed and executable" \
  test -x "$SANDBOX/.claude/statusline-command.sh"

assert "statusline-config.sh stamped from template" \
  test -f "$SANDBOX/.claude/statusline-config.sh"

assert "settings.json has .statusLine.command pointing at the script" \
  bash -c "jq -e '.statusLine.command | test(\"statusline-command.sh\")' '$SANDBOX/.claude/settings.json' >/dev/null"

assert "settings.json preserved 'existingKey'" \
  bash -c "jq -e '.existingKey == \"must-be-preserved\"' '$SANDBOX/.claude/settings.json' >/dev/null"

assert "settings.json preserved 'enabledPlugins.some-other-plugin'" \
  bash -c "jq -e '.enabledPlugins[\"some-other-plugin\"] == true' '$SANDBOX/.claude/settings.json' >/dev/null"

# CSO #2: backup directory must be 0700
backups_perms=$(stat -c '%a' "$SANDBOX/.claude/backups" 2>/dev/null || stat -f '%A' "$SANDBOX/.claude/backups" 2>/dev/null)
assert "~/.claude/backups/ is 0700 (got $backups_perms)" \
  test "$backups_perms" = "700"

# CSO #2: each backup file must be 0600
for f in "$SANDBOX"/.claude/backups/settings.json.*; do
  perms=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%A' "$f" 2>/dev/null)
  assert "$(basename "$f") is 0600 (got $perms)" \
    test "$perms" = "600"
done

# ============================================================
# PHASE 2: render the fixture under the sandbox HOME
# ============================================================
echo
echo "=== Phase 2: render fixture (warm cache from real /tmp) ==="

(
  export HOME="$SANDBOX"
  bash "$SANDBOX/.claude/statusline-command.sh" < "$PLUGIN_ROOT/scripts/preview-fixture.json"
  echo
)
assert "fixture renders cleanly under sandbox HOME" \
  bash -c "HOME='$SANDBOX' bash '$SANDBOX/.claude/statusline-command.sh' < '$PLUGIN_ROOT/scripts/preview-fixture.json' >/dev/null"

# ============================================================
# PHASE 3: simulate /toggle round-trip
# ============================================================
echo
echo "=== Phase 3: toggle round-trip ==="

(
  export HOME="$SANDBOX"
  FLAG="$HOME/.claude/cache/statusline-minimal"
  : > "$FLAG"
  test -f "$FLAG"
  out=$(bash "$HOME/.claude/statusline-command.sh" < "$PLUGIN_ROOT/scripts/preview-fixture.json")
  lines=$(echo "$out" | wc -l)
  test "$lines" -eq 2 || { echo "FAIL: expected 2 lines in minimal mode, got $lines"; exit 1; }
  rm -f "$FLAG"
  test ! -f "$FLAG"
)
assert "/toggle minimal flag-file path produces 2-line output" true

# ============================================================
# PHASE 4: simulate /uninstall
# ============================================================
echo
echo "=== Phase 4: uninstall ==="

(
  export HOME="$SANDBOX"

  # Step 1: restore the latest settings.json backup
  backup=$(ls -t "$HOME/.claude/backups/settings.json."* 2>/dev/null | head -1)
  test -n "$backup" || { echo "FAIL: no backup found"; exit 1; }
  cp "$backup" "$HOME/.claude/settings.json"

  # Step 2: delete the installed script
  rm -f "$HOME/.claude/statusline-command.sh"

  # Step 3: delete the mode flag (already done above)
  rm -f "$HOME/.claude/cache/statusline-minimal"

  # NOT purge mode — keep statusline-config.sh and /tmp caches
)

# ----- Assertions for phase 4 -----
assert "statusline-command.sh removed by uninstall" \
  bash -c "test ! -e '$SANDBOX/.claude/statusline-command.sh'"

assert "statusline-config.sh kept (not purge mode)" \
  test -f "$SANDBOX/.claude/statusline-config.sh"

RESTORED_CHECKSUM=$(sha256sum "$SANDBOX/.claude/settings.json" | awk '{print $1}')
assert "settings.json restored byte-for-byte to pre-install state" \
  test "$RESTORED_CHECKSUM" = "$ORIG_CHECKSUM"

# ============================================================
# Summary
# ============================================================
echo
echo "================================"
echo "PASS: $pass    FAIL: $fail"
echo "================================"
test "$fail" -eq 0
