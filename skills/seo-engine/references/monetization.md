# Monetization: affiliate links in every article and page

Every article and page must monetize the products it discusses. This runs alongside
`writing-rules.md`: the same bar-test, anti-slop and accuracy rules apply to every sentence
added here, including the disclosure.

## Amazon Associates (primary source)
- Every product mentioned in an article or page must be linked, using Amazon Associates as the
  primary source.
- Use the exact tag from the `AMAZON_ASSOCIATES_TAG` env var. Read it fresh from the environment
  each run; never invent, guess, or reuse a remembered tag.
- Only append the tag to a REAL Amazon product URL found live during the run (search / WebFetch
  Amazon during research). **Never fabricate a product URL or ASIN.** If the exact product page
  cannot be verified live, do not link it: use the placeholder rule below instead of guessing.
- Append the tag correctly as a query param on the real `amazon.com` product URL: `?tag=<TAG>` if
  the URL has no query string yet, `&tag=<TAG>` if it already has one. Never overwrite an existing
  `tag=` param with a different value.

## Brands thin on Amazon (placeholder rule, never a guessed link)
- For specialty/outdoor-direct brands where Amazon coverage of the exact product is thin or
  absent (REI, Backcountry, Patagonia, Osprey, and similar), do **not** invent a link to their own
  site or any other retailer.
- Instead, leave this exact placeholder comment immediately after the product mention:
  `<!-- AFFILIATE: [brand] [product name] - manual link needed -->`
  The human fills in the real affiliate link before publishing.
- Never guess a retailer URL, product slug, or affiliate program link for these brands. A wrong or
  dead link is worse than a placeholder.

## Linking style
- Link naturally, inline, in the sentence where the product is genuinely recommended or discussed.
  Never a bolted-on list at the end ("Products mentioned:" dumps are banned).
- One link per distinct product per article; do not relink the same product repeatedly.
- Anchor text is the product's real name (e.g. "Osprey Atmos AG 65"), never "click here" / "buy
  here" / "this link" (also banned by writing-rules.md's anchor rule).

## Product coverage: one hero recommendation, the rest woven in naturally
These rules exist because identical pros/cons boxes stacked under every H2 read as mechanical and
templated, not because the underlying monetization rules changed. The existing rules still apply
without exception: never invent a link, never force a product mention into a section it doesn't
belong in, and the placeholder rule still governs any brand thin on Amazon.
- **4-5 affiliate links per article is the standard target** (long-form, 2,500+ words, where
  products are genuinely relevant). Fewer is fine when the topic only supports one or two genuine
  recommendations; never pad to hit the number.
- **One pros/cons block per article, maximum** (see `design-components.md` for the exact markup),
  reserved for the single main recommended product: the one thing you'd tell a friend to buy if
  they only bought one thing. Every other product gets woven in naturally instead of a repeated box:
  - a short **"recommended gear" list** near the end (3-5 items, product name as the link, one
    clause on why), or
  - an **inline contextual link** in the sentence where the product comes up naturally, or
  - a **row in a comparison table** when the products genuinely differ on measurable specs (see
    writing-rules.md's structural-variety section).
  Never a repeated pros/cons box per product: that is exactly the mechanical pattern this rule
  replaces.
- **CTA button is reserved for the main recommendation's pros/cons block and the entries in the
  recommended-gear list.** Do not attach a CTA button to every inline mention: an inline contextual
  link in running prose is just a normal text link, no button.

## FTC disclosure (mandatory, exactly once per piece, exact wording)
- Every article or page carrying at least one affiliate link must include the disclosure near the
  top, after the quick-answer intro and before the first product recommendation, using the
  `AffiliateDisclosure` markup from `design-components.md`. Use this exact sentence, every time,
  every site unless a site's own config overrides it: "This post contains affiliate links; if you
  buy through one, we may earn a small commission at no extra cost to you." One sentence, one
  disclosure per piece, never repeated per link, never legalese, never expanded or reworded.

## Verification gate (mandatory, before save)
- Every emitted Amazon link must point to a real, live product URL fetched/verified **during this
  run**, with the tag correctly appended. Never reuse a link from a previous article without
  re-verifying it still resolves.
- Every placeholder must use the exact comment format above so it is grep-able for manual
  follow-up. Before shipping the draft, count product mentions vs (real links + placeholders) to
  catch any product that got neither.
- If `AMAZON_ASSOCIATES_TAG` is unset or empty, emit **no** Amazon link with a blank tag: fall back
  to the placeholder comment for every product mention instead, and note "AMAZON_ASSOCIATES_TAG
  missing" in the status line.
