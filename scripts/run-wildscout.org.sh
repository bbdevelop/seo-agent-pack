#!/usr/bin/env bash
# Cron wrapper for wildscout.org. Usage: run-wildscout.org.sh <article|page|sunday|index>
#
# Runs headless via `claude -p`, hard-timeboxed so a hung run can never block the next
# scheduled job. Every path (success, timeout, error, or a run that silently wrote no
# status line) ends in exactly one status-file line and, on failure, a Telegram alert
# instead of failing silently. On a successful article/page/sunday run, commits and
# pushes whatever draft-only content the run produced so the Pages CMS edit link in the
# Telegram summary actually works by morning -- this never flips draft:true to false,
# it only gets the already-draft file onto GitHub.
set -uo pipefail

# cron runs with a near-empty PATH (no .bashrc/.profile), so `claude` (~/.local/bin) and
# node/npx (nvm) would otherwise be invisible to this script.
export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.18.0/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/sbin:/usr/sbin"

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_REPO="$HOME/wildscout-site"
cd "$PACK_DIR"

set -a
source .env
set +a

JOB="${1:-}"
TODAY="$(date +%F)"
# Absolute paths throughout: fail()/alert() may fire after we've cd'd into $SITE_REPO
# for the git step, and a relative path would silently write to the wrong place.
STATUS_FILE="$PACK_DIR/status/${TODAY}.txt"
LOG_FILE="$PACK_DIR/logs/${TODAY}-${JOB}.log"
SITE_JSON="$PACK_DIR/sites/wildscout.org.json"
PROMPT_FILE="$PACK_DIR/prompts/nightly-run-wildscout.org.md"
LOCK_FILE="/tmp/wildscout-org-${JOB}.lock"

mkdir -p "$PACK_DIR/status" "$PACK_DIR/logs"

alert() {
  # $1 = message. A Telegram outage must never crash the wrapper itself.
  python3 "$PACK_DIR/scripts/telegram_bot.py" send "$TELEGRAM_CHAT_ID" "$1" >> "$LOG_FILE" 2>&1 || true
}

# Fatal: one status line + one Telegram alert + exit 1.
fail() {
  echo "wildscout.org | ${JOB} | FAILED (${1}, see ${LOG_FILE})" >> "$STATUS_FILE"
  alert "🔴 wildscout.org | ${JOB} FAILED: ${1}
Log: ${LOG_FILE}"
  exit 1
}

# Non-fatal: one status line + one Telegram alert, script continues.
warn() {
  echo "wildscout.org | ${1} | FAILED (${2}, see ${LOG_FILE})" >> "$STATUS_FILE"
  alert "🟠 wildscout.org | ${1} FAILED: ${2}
Log: ${LOG_FILE}"
}

case "$JOB" in
  article|page|sunday)
    exec 9>"$LOCK_FILE"
    flock -n 9 || fail "previous ${JOB} run still in progress (lock held)"

    if ! timeout -k 1m 70m claude -p --dangerously-skip-permissions "$(cat "$PROMPT_FILE")" > "$LOG_FILE" 2>&1; then
      fail "timeout or non-zero exit"
    fi

    # The run is supposed to append its own status line per run-protocol.md. If it
    # exited 0 but didn't, that's a silent failure -- catch it rather than trust the
    # exit code alone.
    if ! grep -q "^wildscout\.org | ${JOB} |" "$STATUS_FILE" 2>/dev/null; then
      fail "exited 0 but wrote no status line"
    fi

    # Auto-commit + push so the Telegram summary's CMS edit link resolves by morning.
    # Scoped to the two directories a nightly run can legitimately touch -- never a
    # blanket `git add -A` -- and it's a no-op if the run only skipped/optimized.
    cd "$SITE_REPO"
    git add src/content public/images
    if ! git diff --cached --quiet; then
      git commit -q -m "Automated ${JOB} run - ${TODAY}

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
      if git push origin main >> "$LOG_FILE" 2>&1; then
        : # pushed clean
      elif git pull --rebase origin main >> "$LOG_FILE" 2>&1 && git push origin main >> "$LOG_FILE" 2>&1; then
        : # a Pages CMS commit had landed first; rebased once and pushed clean
      else
        git rebase --abort >> "$LOG_FILE" 2>&1 || true
        cd "$PACK_DIR"
        fail "git push failed even after one rebase retry -- draft is committed locally only, needs a human"
      fi
    fi
    cd "$PACK_DIR"
    ;;

  index)
    exec 9>"$LOCK_FILE"
    flock -n 9 || fail "previous index run still in progress (lock held)"

    timeout -k 1m 10m python3 scripts/auto_index.py daily "$SITE_JSON" > "$LOG_FILE" 2>&1 \
      || fail "daily indexing failed"

    # Sunday's index run also does the weekly sitemap resubmit + not-indexed report.
    # Non-fatal on its own: the daily job above already succeeded.
    if [ "$(date +%u)" = "7" ]; then
      timeout -k 1m 15m python3 scripts/auto_index.py weekly "$SITE_JSON" >> "$LOG_FILE" 2>&1 \
        || warn "index-weekly" "weekly sitemap resubmit / not-indexed report failed"
    fi
    ;;

  *)
    echo "Usage: $0 <article|page|sunday|index>" >&2
    exit 1
    ;;
esac
