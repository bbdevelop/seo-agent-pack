# Design Components: conversion elements available in wildscout.org articles

wildscout.org's site design (Astro, "Trail Journal" visual direction: Fraunces serif headings,
terracotta accent) ships four reusable conversion components. They exist both as Astro components
(for hand-written `.astro` pages) and as plain HTML block markup you can write directly inside a
markdown post. Since the nightly agent only ever writes markdown files under `src/content/blog/`,
**use the raw HTML markup below**, not the Astro component syntax (that's for reference only, in
case a human later builds a page in `.astro` directly).

## Fixed gotcha (know this if a site's .pages.yml still has it wrong): rich-text body fields destroy these components on every save

If a `.pages.yml` posts collection has `body: { type: rich-text }`, **every single save through
that field is guaranteed to strip these raw-HTML blocks**, not just occasionally. Pages CMS's
rich-text field is a TipTap/ProseMirror WYSIWYG editor with no "raw HTML block" node in its
schema, so it re-serializes any `<div class="...">` it doesn't recognize down to the nearest node
type it does: `pros-cons` divs become `#### Pros` / `#### Cons` headings with bullet lists,
`quick-answer` becomes a plain paragraph, `cta-button` becomes a plain markdown link, and
`disclosure` becomes plain text. This isn't intermittent: it happened on wildscout.org's compass
article three saves in a row, and never happened to the sleeping-pad article only because that one
was never re-saved through the CMS after its components existed (confirmed via git history).

**The fix, not a workaround:** for any collection whose posts use these raw-HTML component blocks,
set `body: { type: code, options: { format: markdown } }` in `.pages.yml` instead of `rich-text`.
Pages CMS's `code` field is a plain-text editor that stores content exactly as typed, with no
parsing or re-serialization, so it round-trips these blocks correctly. wildscout.org's `.pages.yml`
already uses this for its `posts` collection; if you're setting up a new site's `.pages.yml` (or
adding a posts collection to one), configure `body` the same way from the start. Pages pages
without these components (About, Privacy, Terms, etc.) can keep `rich-text` for its nicer editing
UX since there's nothing for it to strip.

## The one hard rule: no blank lines inside a block

Astro's markdown renderer (remark/CommonMark) passes raw HTML straight through, uninterpreted,
as long as it is written as one **contiguous block with no blank line** between the opening tag
and the closing tag. A blank line ends the HTML block early and lets a stray line get parsed as
a separate markdown paragraph, breaking the nesting (an unclosed `<div>` and a dangling `</div>`
on their own). Concretely:

- Write every paragraph inside a component as an explicit `<p>...</p>`, never a markdown blank-line
  paragraph.
- Leave a blank line **before** the block (so it doesn't merge into the previous paragraph) and
  **after** the closing tag, but never inside it.
- Do not use markdown syntax (`**bold**`, `[link](url)`, etc.) inside these blocks; it will not be
  processed. Write raw `<strong>`/`<a>` tags if you need inline formatting.
- Plain markdown images (`![alt](src)`) do NOT need any of this. Keep writing them exactly as
  before; the site's CSS automatically detects a bare image and gives it the wider "breakout"
  treatment. Only the four components below need the raw-HTML block convention.

## Quick answer callout

Use for the direct 2-4 sentence answer at the top of the article (the existing "quick answer"
requirement in `writing-rules.md`). Wrap it in this exact markup, placed right after the affiliate
disclosure line:

```html
<div class="quick-answer">
<span class="quick-answer__label">Quick answer</span>
<p>Your direct answer sentences go here, as one or more &lt;p&gt; tags.</p>
</div>
```

## Pros / cons box

Use in a product section that has a clear pros/cons split. Keep each list to 2-5 short items,
matching the site's existing list-length caps.

```html
<div class="pros-cons">
<div class="pros">
<h4>Pros</h4>
<ul><li>First pro</li><li>Second pro</li><li>Third pro</li></ul>
</div>
<div class="cons">
<h4>Cons</h4>
<ul><li>First con</li><li>Second con</li></ul>
</div>
</div>
```

## Check-price CTA button

Use for the affiliate link on a specific product recommendation, in addition to (not instead of)
the normal inline text link the writing-rules already require. Place it as its own line, directly
after the paragraph that recommends the product. `rel="sponsored noopener"` and `target="_blank"`
are required (matches the site's existing convention and Google's affiliate-link guidance).

```html
<a class="cta-button" href="https://www.amazon.com/dp/EXAMPLE?tag=YOURTAG" rel="sponsored noopener" target="_blank">Check Price on Amazon</a>
```

Use natural, specific button text ("Check Price on Amazon", "Check Price at REI"), never generic
"Click Here" / "Buy Now" (the anchor-text rule in `writing-rules.md` still applies).

## Affiliate disclosure line

The one-sentence FTC disclosure `monetization.md` already requires near the top of every article.
Give it this class so it renders as a subtle, contained strip rather than a plain paragraph:

```html
<p class="disclosure">This post contains affiliate links; if you buy through one, we may earn a small commission at no extra cost to you.</p>
```

Place it as the very first thing in the article body, before the quick-answer callout.

## Order at the top of an article

```html
<p class="disclosure">...</p>

<div class="quick-answer">
<span class="quick-answer__label">Quick answer</span>
<p>...</p>
</div>
```

Then continue with the first H2 as normal.
