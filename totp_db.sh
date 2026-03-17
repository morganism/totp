#!/usr/bin/env bash
# totp_db.sh — SQLite3-backed TOTP account/secret store
# Morgan / morganism — unix philosophy: do one thing well
#
# Usage:
#   source totp_db.sh             # load functions into current shell
#   totp_init                     # create DB + table (idempotent)
#   totp_add    <account> <secret>
#   totp_delete <account>
#   totp_secret <account>         # lookup secret by account
#   totp_account <secret>         # lookup account by secret

# ── Config ────────────────────────────────────────────────────────────────────

TOTP_DB="${TOTP_DB:-${HOME}/.local/share/totp/totp.db}"

# ── Internal helper ───────────────────────────────────────────────────────────

_totp_db() {
  sqlite3 "${TOTP_DB}" "$@"
}

# ── Init ──────────────────────────────────────────────────────────────────────

totp_init() {
  local db_dir
  db_dir="$(dirname "${TOTP_DB}")"

  mkdir -p "${db_dir}" || { echo "[totp] ERROR: cannot create ${db_dir}" >&2; return 1; }
  chmod 700 "${db_dir}"

  _totp_db <<'SQL'
CREATE TABLE IF NOT EXISTS totp (
  account TEXT NOT NULL UNIQUE,
  secret  TEXT NOT NULL
);
SQL

  chmod 600 "${TOTP_DB}"
  echo "[totp] DB ready: ${TOTP_DB}"
}

# ── 1. Add account + secret ───────────────────────────────────────────────────

totp_add() {
  local account="${1:?totp_add: account required}"
  local secret="${2:?totp_add: secret required}"

  totp_init &>/dev/null   # idempotent — no-op if already exists

  _totp_db "INSERT OR REPLACE INTO totp (account, secret) VALUES ('${account}', '${secret}');" \
    && echo "[totp] added: ${account}" \
    || { echo "[totp] ERROR: insert failed" >&2; return 1; }
}

# ── 2. Delete account ─────────────────────────────────────────────────────────

totp_delete() {
  local account="${1:?totp_delete: account required}"

  local rows
  rows=$(_totp_db "SELECT changes() FROM totp WHERE account='${account}'; \
                   DELETE FROM totp WHERE account='${account}'; \
                   SELECT changes();")

  # sqlite3 returns the change count on the last SELECT changes()
  local deleted
  deleted=$(echo "${rows}" | tail -1)

  if [[ "${deleted}" -gt 0 ]]; then
    echo "[totp] deleted: ${account}"
  else
    echo "[totp] not found: ${account}" >&2
    return 1
  fi
}

# ── 3. Lookup account by secret ───────────────────────────────────────────────

totp_account() {
  local secret="${1:?totp_account: secret required}"

  local result
  result=$(_totp_db "SELECT account FROM totp WHERE secret='${secret}' LIMIT 1;")

  if [[ -n "${result}" ]]; then
    echo "${result}"
  else
    echo "[totp] no account found for that secret" >&2
    return 1
  fi
}

# ── 4. Lookup secret by account ───────────────────────────────────────────────

totp_secret() {
  local account="${1:?totp_secret: account required}"

  local result
  result=$(_totp_db "SELECT secret FROM totp WHERE account='${account}' LIMIT 1;")

  if [[ -n "${result}" ]]; then
    echo "${result}"
  else
    echo "[totp] no secret found for account: ${account}" >&2
    return 1
  fi
}

# ── 5. List all accounts (bonus — too useful to omit) ─────────────────────────

totp_list() {
  _totp_db ".mode column" \
            ".headers on" \
            "SELECT account, substr(secret,1,4) || '...' AS secret_hint FROM totp ORDER BY account;"
}

# ── Self-test (run directly, not sourced) ─────────────────────────────────────

_totp_selftest() {
  echo "=== TOTP DB self-test ==="
  local tmp_db
  tmp_db="$(mktemp /tmp/totp_test_XXXXXX.db)"
  TOTP_DB="${tmp_db}"

  totp_init
  totp_add    "github:morgan"     "JBSWY3DPEHPK3PXP"
  totp_add    "aws:root"          "AAAABBBBCCCCDDDD"
  totp_add    "gitlab:morgan"     "ZZZZYYYY12345678"

  echo "--- list ---"
  totp_list

  echo "--- secret for github:morgan ---"
  totp_secret "github:morgan"

  echo "--- account for AAAABBBBCCCCDDDD ---"
  totp_account "AAAABBBBCCCCDDDD"

  echo "--- delete aws:root ---"
  totp_delete "aws:root"
  totp_list

  echo "--- delete non-existent ---"
  totp_delete "no:such:account" || true

  rm -f "${tmp_db}"
  echo "=== self-test complete ==="
}

# Run self-test only when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _totp_selftest
fi
