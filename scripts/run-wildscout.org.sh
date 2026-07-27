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

# cron can invoke this under a stripped environment where HOME itself is unset (not just
# missing from PATH) -- under `set -u` that kills the script on the very next `$HOME`
# reference below, before any log or alert can fire. Default it explicitly rather than
# trusting the environment. (Root cause of the 2026-07-26 "HOME: unbound variable" failure.)
: "${HOME:=/home/bb}"
export HOME

# Precautionary: keep CLAUDE_CODE_*/CLAUDECODE/AI_AGENT vars out of `claude -p` below. NOTE:
# tested directly on 2026-07-27 and this alone does NOT fix the "what would you like help
# with" failure (see the cwd fix further down, which is the actual cause). Harmless either way,
# so left in as defensive hygiene against a live Claude Code session's Bash tool leaking these
# in if this script is ever run manually from inside one.
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
      CLAUDE_CODE_EXECPATH AI_AGENT CLAUDE_PID CLAUDE_EFFORT

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
LOG_DIR="$PACK_DIR/logs"
LOG_FILE="$LOG_DIR/${TODAY}-${JOB}.log"
SITE_JSON="$PACK_DIR/sites/wildscout.org.json"
PROMPT_FILE="$PACK_DIR/prompts/nightly-run-wildscout.org.md"
LOCK_FILE="/tmp/wildscout-org-${JOB}.lock"
# claude -p must NEVER run with cwd inside $PACK_DIR -- see the article|page|sunday case below.
CLAUDE_RUN_CWD="$HOME/.wildscout-cron-cwd"

mkdir -p "$PACK_DIR/status" 2>/dev/null

# Sends a Telegram message without depending on the log file being writable. Used by the
# pre-flight check below (before we know the log dir even works) and by alert() once it's
# confirmed writable -- alert() redirects its own output INTO the log, so if that redirect
# itself is what's broken, alert() silently never runs at all (the exact 2026-07-26 failure:
# logs/ was root-owned, `>> "$LOG_FILE"` failed before python3 ever started, and `|| true`
# swallowed it, so even the "FAILED" Telegram alert never sent).
alert_raw() {
  python3 "$PACK_DIR/scripts/telegram_bot.py" send "$TELEGRAM_CHAT_ID" "$1" > /dev/null 2>&1 || true
}

# Pre-flight: the log directory must exist and be writable by this user, or every FAILED
# status below gets reported with zero log to explain why -- the exact silent failure above.
if ! mkdir -p "$LOG_DIR" 2>/dev/null || [ ! -w "$LOG_DIR" ]; then
  alert_raw "🔴 wildscout.org | ${JOB} FAILED: log directory ${LOG_DIR} does not exist or is not writable by $(whoami) (uid $(id -u)) -- no log was written for this run"
  echo "wildscout.org | ${JOB} | FAILED (log directory ${LOG_DIR} not writable)" >> "$STATUS_FILE" 2>/dev/null || true
  exit 1
fi

# First action once we know we CAN log: a run that dies immediately after this (bad lock,
# claude -p erroring instantly) must never report FAILED against an empty or missing log.
echo "$(date '+%F %T') | ${JOB} | started" >> "$LOG_FILE"

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

    # Guard against burning a whole run on nothing: a missing file, a bad path, or an
    # unquoted variable that silently expands to empty must abort BEFORE calling claude,
    # not after 70 minutes of doing nothing useful with an empty instruction.
    if [ ! -s "$PROMPT_FILE" ]; then
      fail "prompt file ${PROMPT_FILE} is missing or empty -- refusing to call claude with no instructions"
    fi
    PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
    if [ -z "$PROMPT_CONTENT" ]; then
      fail "prompt file ${PROMPT_FILE} read as empty -- refusing to call claude with no instructions"
    fi

    # Run claude -p from a dedicated, empty directory -- NEVER from $PACK_DIR. Confirmed by
    # direct repro (2026-07-27): invoking `claude -p` with cwd inside this project's own
    # directory reliably makes it treat the whole prompt as background context and reply with
    # a generic "what would you like help with", doing zero real work -- with no error and no
    # non-zero exit for this script to catch. 3/3 failures from $PACK_DIR, 4/4 successes from a
    # neutral cwd, confirmed via the session transcripts themselves: broken runs are one short
    # text turn with zero tool calls, working runs show full multi-step tool engagement and
    # correct skill loading. Literal session resumption (-c/--continue) was ruled out
    # structurally -- every run creates its own fresh session file. Every path the actual task
    # touches is already absolute throughout this pack, so this has no effect on what the run
    # can do; it only avoids whatever project-directory-scoped state causes the failure.
    mkdir -p "$CLAUDE_RUN_CWD"
    cd "$CLAUDE_RUN_CWD"
    timeout -k 1m 70m claude -p --dangerously-skip-permissions "$PROMPT_CONTENT" >> "$LOG_FILE" 2>&1
    CLAUDE_EXIT=$?
    cd "$PACK_DIR"
    if [ "$CLAUDE_EXIT" -ne 0 ]; then
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

    timeout -k 1m 10m python3 scripts/auto_index.py daily "$SITE_JSON" >> "$LOG_FILE" 2>&1 \
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
