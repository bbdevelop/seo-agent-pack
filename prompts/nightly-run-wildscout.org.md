# Nightly run prompt: wildscout.org

Sent to `claude -p` every scheduled run (article/page nights and the Sunday optimization) by
`run.sh` after sourcing `.env`. Filled in from `templates/nightly-run-prompt.md`.

---

Autonomous scheduled SEO run. Do not ask questions; execute or skip with a status line. Load the
seo-engine skill and my site config at /home/bb/seo-agent-pack/sites/wildscout.org.md. Follow
run-protocol.md for today's weekday job (article, page, or Sunday optimization). Build the keyword
brief from DataForSEO (scripts/dataforseo_keywords.py) and Search Console (scripts/gsc_query.py)
only, apply the five gates, do the competitor pass and write the differentiation sentence, write
the piece under writing-rules.md with the anti-slop and humanizer passes, monetize every product
mention per monetization.md (real Amazon Associates links or the manual-link placeholder, one FTC
disclosure). For article and page jobs, do NOT generate images yourself: write each image's full
500-800 word prompt per image-prompts.md and save it to
/home/bb/seo-agent-pack/status/pending-images/<slug>/<image-filename-without-extension>.txt, one
file per required image, the filename matching the image's reference in the body exactly (featured
image included). A separate deterministic job generates, verifies, commits, and notifies once
they're done -- do not call scripts/gemini_image.py directly and do not wait for it. Save
everything as a draft (articles and pages both draft-only for this site) referencing the expected
final image paths, append one status line to /home/bb/seo-agent-pack/status/<YYYY-MM-DD>.txt
(today's date) noting images are pending, and send NO Telegram message for article/page jobs -- the
images job sends the single notification once the piece is actually complete and reviewable. Sunday
optimization jobs are unaffected: they still send their own summary via scripts/telegram_bot.py as
before.
