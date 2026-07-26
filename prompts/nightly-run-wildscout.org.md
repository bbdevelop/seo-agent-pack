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
disclosure), generate images per image-prompts.md with scripts/gemini_image.py and verify every
file resolves, save everything as a draft (articles and pages both draft-only for this site), append
one status line to /home/bb/seo-agent-pack/status/<YYYY-MM-DD>.txt (today's date), and send me the
Telegram summary via scripts/telegram_bot.py.
