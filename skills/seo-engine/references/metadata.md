# Metadata: which frontmatter field feeds which tag

Every page on a site built with this pack's conventions gets its `<title>`, meta description,
canonical URL, Open Graph/Twitter tags, and JSON-LD structured data generated automatically from a
reusable head component (on wildscout.org: `src/components/SeoHead.astro`, wired into
`BaseLayout.astro` and called by `BlogLayout.astro`/`PageLayout.astro`/the homepage). Nothing here
needs hand-coded HTML in a post. What it needs instead is the frontmatter and body structure below,
filled in every time, so the head component has real data to work with instead of falling back to
something generic.

## Article frontmatter -> tags

| Frontmatter field | Feeds |
|---|---|
| `title` | `<title>`, `og:title`, `twitter:title`, JSON-LD `Article.headline` |
| `description` | meta description, `og:description`, `twitter:description`, JSON-LD `Article.description` |
| `heroImage` | in-page hero `<img>`, and (via its `.webp` sibling, see below) `og:image` / `twitter:image` / JSON-LD `Article.image` |
| `pubDate` | visible post date, JSON-LD `Article.datePublished` |
| `updatedDate` | JSON-LD `Article.dateModified` (falls back to `pubDate` if not set: only add this field when the post is genuinely edited after publishing) |
| `category` | category-page listing; not currently in structured data |
| `draft` | excludes the post from the sitemap and the production build entirely, and adds `<meta name="robots" content="noindex, nofollow">` to the dev-only preview route |
| the post's slug (filename) | canonical URL and JSON-LD `mainEntityOfPage`, always `https://<domain>/<slug>/` |

**`description` is optional in the zod schema but never actually optional**: every one of title,
meta description, OG, Twitter, and JSON-LD depends on it. A post saved without one silently loses
its meta description, its social preview text, and part of its structured data. Always write one
(this is also required by writing-rules.md's meta-description length rule already).

## Hero image: the OG image is not the in-page image

`image-prompts.md` already generates an AVIF (in-page) and a WebP (OG/social) copy of every hero
image with the same basename. The head component derives `og:image`/`twitter:image` by swapping
`heroImage`'s `.avif` extension for `.webp` automatically. **This means both files must exist next
to each other with matching basenames** (`slug.avif` + `slug.webp`), which is already the normal
output of the image pipeline. Don't rename one without the other, and don't reference a hero image
that has no `.webp` sibling. If `heroImage` is missing entirely, the head component falls back to a
site-wide default OG image instead.

## FAQPage structured data comes from the FAQ section's own markdown structure

No separate FAQ frontmatter field exists. FAQPage JSON-LD is parsed directly out of the body at
build time, from exactly the structure writing-rules.md already requires:

```
## Frequently Asked Questions

### A natural-language question?

One paragraph answer, immediately after the question, no blank-line-separated second paragraph.

### Another question?

...
```

- The parser looks for an H2 whose text contains "frequently asked questions" (case-insensitive),
  then reads every H3 inside that section as a question.
- **Only the first paragraph after each `### Question` becomes that question's JSON-LD answer text.**
  A second paragraph, or a closing CTA-style paragraph tacked on after the very last FAQ answer with
  no heading in between, is NOT included. If you need the reader-facing closing paragraph after the
  FAQ (a common, fine pattern per writing-rules.md's "no Conclusion heading" rule), keep it there for
  readers; just don't expect it to appear in the FAQ's structured data, and don't rely on a second
  paragraph to carry meaning for an FAQ answer since it won't reach search engines.
- Markdown links/emphasis inside an answer are stripped to plain text for JSON-LD (a search result
  can't render a clickable link), but stay as real markdown for the reader-facing HTML.
- A post with no "Frequently Asked Questions" H2 simply gets no FAQPage schema. Since
  writing-rules.md already requires an FAQ section on every article, this should never happen in
  practice; if a post is missing one, that is itself a self-review gate failure, not a metadata gap.

## Homepage and category pages

These don't come from post frontmatter at all, they're hand-written directly in the page source
(`src/pages/index.astro`, `src/lib/categories.ts`) since there's no article driving them. Keep them
updated the same way: a real title and a real description, not a placeholder, whenever the site's
positioning or category set changes. The homepage additionally carries Organization + WebSite
JSON-LD (site-wide identity, not per-page content) and Article pages carry Article + FAQPage
JSON-LD; nothing else on the site emits structured data.

## Draft safety

A draft is already excluded from the sitemap and never gets a production route at all (`draft: true`
posts are filtered out of `getStaticPaths` at build time), so there is no live URL for search engines
to find in the first place. The `noindex` meta tag is belt-and-suspenders for the dev-only preview
route, not something that does anything in production. Never rely on `noindex` alone to keep a draft
out of search results: `draft: true` is the actual mechanism.
