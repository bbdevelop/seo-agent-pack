#!/usr/bin/env bash
# Deterministic image-generation catch-up job for wildscout.org. Runs on its own schedule after
# article/page nights, picks up any prompt files the write step saved to status/pending-images/,
# generates each image via gemini_image.py with its OWN per-image timeout, commits + pushes the
# finished images, and sends the single "draft ready to review" Telegram notification once a slug's
# images are all done -- the write step itself sends nothing.
#
# The design point: this is a plain deterministic bash loop, no agent, no backgrounding, no
# notification-wait. That's what makes it structurally unable to hang the way the 2026-07-29 04:00
# article run did (70 minutes of near-total silence waiting on 8 backgrounded image jobs inside a
# headless claude -p session). Each image call here has its own hard timeout; nothing here can block
# anything else here.
set -uo pipefail

: "${HOME:=/home/bb}"
export HOME
export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.18.0/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/sbin:/usr/sbin"

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_REPO="$HOME/wildscout-site"
cd "$PACK_DIR"

set -a
source .env
set +a

JOB="images"
TODAY="$(date +%F)"
STATUS_FILE="$PACK_DIR/status/${TODAY}.txt"
LOG_DIR="$PACK_DIR/logs"
LOG_FILE="$LOG_DIR/${TODAY}-${JOB}.log"
PENDING_DIR="$PACK_DIR/status/pending-images"
LOCK_FILE="/tmp/wildscout-org-images.lock"

mkdir -p "$PACK_DIR/status" 2>/dev/null

alert_raw() {
  python3 "$PACK_DIR/scripts/telegram_bot.py" send "$TELEGRAM_CHAT_ID" "$1" > /dev/null 2>&1 || true
}

if ! mkdir -p "$LOG_DIR" 2>/dev/null || [ ! -w "$LOG_DIR" ]; then
  alert_raw "🔴 wildscout.org | images FAILED: log directory ${LOG_DIR} not writable -- no log for this run"
  echo "wildscout.org | images | FAILED (log directory ${LOG_DIR} not writable)" >> "$STATUS_FILE" 2>/dev/null || true
  exit 1
fi

echo "$(date '+%F %T') | images | started" >> "$LOG_FILE"

alert() {
  python3 "$PACK_DIR/scripts/telegram_bot.py" send "$TELEGRAM_CHAT_ID" "$1" >> "$LOG_FILE" 2>&1 || true
}

fail() {
  echo "wildscout.org | images | FAILED (${1}, see ${LOG_FILE})" >> "$STATUS_FILE"
  alert "🔴 wildscout.org | images FAILED: ${1}
Log: ${LOG_FILE}"
  exit 1
}

exec 9>"$LOCK_FILE"
flock -n 9 || fail "previous images run still in progress (lock held)"

mkdir -p "$PENDING_DIR"

if [ -z "$(ls -A "$PENDING_DIR" 2>/dev/null)" ]; then
  echo "$(date '+%F %T') | images | nothing pending" >> "$LOG_FILE"
  exit 0
fi

ANY_FAILURE=0
FAILED_SUMMARY=""

for slug_dir in "$PENDING_DIR"/*/; do
  [ -d "$slug_dir" ] || continue
  slug="$(basename "$slug_dir")"
  OUTDIR="$SITE_REPO/public/images/blog/${slug}"
  CONTENT_FILE="$SITE_REPO/src/content/blog/${slug}.md"
  mkdir -p "$OUTDIR"

  slug_failed=0
  for prompt_file in "$slug_dir"*.txt; do
    [ -f "$prompt_file" ] || continue
    image_name="$(basename "$prompt_file" .txt)"

    # Already generated (e.g. a retry after a previous partial run) -- just clean up the prompt.
    if [ -f "$OUTDIR/${image_name}.avif" ] && [ -f "$OUTDIR/${image_name}.webp" ]; then
      rm -f "$prompt_file"
      continue
    fi

    echo "$(date '+%F %T') | images | generating ${slug}/${image_name}" >> "$LOG_FILE"
    if timeout -k 15s 3m python3 "$PACK_DIR/scripts/gemini_image.py" "$prompt_file" "$OUTDIR" "$image_name" >> "$LOG_FILE" 2>&1; then
      rm -f "$prompt_file"
    else
      echo "$(date '+%F %T') | images | FAILED ${slug}/${image_name} (timeout or error, prompt kept for retry)" >> "$LOG_FILE"
      slug_failed=1
      ANY_FAILURE=1
      FAILED_SUMMARY="${FAILED_SUMMARY}
- ${slug}/${image_name}"
    fi
  done

  if [ "$slug_failed" -eq 0 ]; then
    # Every image for this slug is done. Directory should now be empty; drop it.
    rmdir "$slug_dir" 2>/dev/null || true

    cd "$SITE_REPO"
    git add "public/images/blog/${slug}"
    if ! git diff --cached --quiet; then
      git commit -q -m "Automated images run - ${slug} - ${TODAY}

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
      if git push origin main >> "$LOG_FILE" 2>&1; then
        : # pushed clean
      elif git pull --rebase origin main >> "$LOG_FILE" 2>&1 && git push origin main >> "$LOG_FILE" 2>&1; then
        : # something else landed first; rebased once and pushed clean
      else
        git rebase --abort >> "$LOG_FILE" 2>&1 || true
        cd "$PACK_DIR"
        echo "wildscout.org | images | FAILED (git push failed for ${slug} even after one rebase retry, see ${LOG_FILE})" >> "$STATUS_FILE"
        alert "🔴 wildscout.org | images FAILED: git push failed for ${slug} -- images committed locally only, needs a human
Log: ${LOG_FILE}"
        ANY_FAILURE=1
        continue
      fi
    fi
    cd "$PACK_DIR"

    TITLE="$(grep -m1 '^title:' "$CONTENT_FILE" 2>/dev/null | sed -E 's/^title:\s*"?//; s/"?\s*$//')"
    ENCODED_PATH="$(printf '%s' "src/content/blog/${slug}.md" | sed 's#/#%2F#g')"
    CMS_LINK="https://app.pagescms.org/bbdevelop/wildscout-site/main/collection/posts/edit/${ENCODED_PATH}"

    echo "wildscout.org | images | NEW ARTICLE READY (draft) - https://wildscout.org/${slug}/ - \"${TITLE}\" - Edit: ${CMS_LINK}" >> "$STATUS_FILE"
    alert "🟢 wildscout.org | draft ready to review: ${TITLE}
https://wildscout.org/${slug}/
Edit: ${CMS_LINK}"
  fi
done

if [ "$ANY_FAILURE" -ne 0 ] && [ -n "$FAILED_SUMMARY" ]; then
  echo "wildscout.org | images | INCOMPLETE (some images still failing, prompts kept for retry: ${FAILED_SUMMARY//$'\n'/ }, see ${LOG_FILE})" >> "$STATUS_FILE"
  alert "🟠 wildscout.org | images: some images still failing after retry, prompts kept for tomorrow's run:${FAILED_SUMMARY}
Log: ${LOG_FILE}"
fi

[ "$ANY_FAILURE" -eq 0 ] || exit 1
exit 0
