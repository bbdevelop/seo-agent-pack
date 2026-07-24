---
name: seo-engine
description: Autonomous SEO content engine. Use on every scheduled SEO run (article, page, or Sunday optimization) together with the site config file. Holds the keyword method, writing rules, image method and run protocol.
---

# SEO Engine

The method for one nightly run. Always load this skill AND the site config file, then follow the references in this order:

1. `references/run-protocol.md`: what today's job is (article day, page day, or optimization), the pre-flight checks, and the delivery rules. Start here every run.
2. `references/keyword-method.md`: how the day's keyword gets chosen. Five gates, all mandatory: relevance, verified volume, intent, winnability, anti-cannibalization. Then the competitor pass: read the top 3, map their coverage, list their gaps, and write the one-sentence reason yours will be better. Cover everything they cover, then add what they miss. No sentence, no article.
3. `references/writing-rules.md`: how the piece gets written. Structure, anti-slop rules, the humanizer pass, titles, metas, FAQ, internal links, and the self-review checklist. One corrective pass maximum, then ship as draft or flag.
4. `references/monetization.md`: how every product mention gets monetized. Amazon Associates links verified live during the run, the placeholder rule for brands thin on Amazon, one FTC disclosure per piece. Never invent or guess a link.
5. `references/image-prompts.md`: how every image gets generated. 500+ word prompts, literal subjects, your fixed site palette, and the verification gate (every referenced image must resolve before the run counts as done).
6. `references/eeat.md`: authorship and trust signals. Always the WildScout Team byline, never an individual name or an invented personal testing anecdote, every claim sourced to manufacturer data/verified owner reviews/independent test standards, affiliate disclosure near the top of every piece.
7. `references/design-components.md`: the site's reusable conversion components (quick-answer callout, pros/cons box, check-price CTA button, affiliate disclosure strip) and the exact raw-HTML markdown syntax to write them in, including the no-blank-lines-inside-a-block rule. Plain images still just use normal markdown.

Hard rules that override everything: content saves as DRAFT unless the site config explicitly allows live publishing for that content type; secrets from .env are never printed, copied or committed; every factual claim is verified live during the run or deleted; every product mention is a real, verified affiliate link or an explicit manual-link placeholder, never a guessed URL; every byline is the WildScout Team, never an individual name or an unverified first-person testing claim; one status line gets appended to the daily status file at the end of every run, success or failure.
