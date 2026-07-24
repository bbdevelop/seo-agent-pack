# Site config: wildscout.org

- Domain and language: wildscout.org, English
- What the business sells, in one sentence: Camping and outdoor gear advice, reviews and affiliate buying recommendations.
- Audience: People planning camping and hiking trips who want gear reviews and honest buying advice.
- Allowed topic lanes: tents, backpacks and carrying gear, camp cooking, sleeping systems, navigation and safety.
- Forbidden lanes: hunting content, firearms, extreme survivalist content.
- Voice: persona = an experienced friend who's been camping for years; rhythm = practical and direct, no corporate tone; brand mentions = rarely (only when naturally relevant, no stuffing); CTAs = point to the relevant gear review/roundup or affiliate link, worded as a genuine recommendation, never "buy now" hype; forbidden claims = never claim to have personally tested gear the site hasn't verified testing real specs/prices, never overstate affiliate neutrality.
- Currency: USD
- Image palette (fixed, every image): background #2D3B2A, accent #C97D3E, people no, text in images no.
- Blog location and draft mechanism: repo path ~/wildscout-site (GitHub: bbdevelop/wildscout-site, deployed via Cloudflare Workers). Posts are markdown files in `src/content/blog/*.md` with frontmatter `draft: true|false` (Astro content collection, schema in `src/content.config.ts`). Setting `draft: true` keeps a post out of the sitemap and out of `getStaticPaths` (see `src/pages/[slug].astro`; post URLs are at the site root, e.g. `wildscout.org/my-post/`, with content files still stored under `src/content/blog/`), so it never builds a live route. A companion registry at `src/content/registry.json` tracks every post (any status) with slug, title, targetKeyword, status, type, pubDate, file -- read this file in full during every pre-flight draft check, not just the sitemap.
- Category field (required): every post's frontmatter must set `category` to exactly one of: `tents`, `backpacks`, `cooking`, `sleep-systems`, `navigation-safety` (enforced by the zod enum in `src/content.config.ts` -- the build fails without a valid value). Pick the lane that matches the topic; these are the same lanes listed under "Allowed topic lanes" above. Posts are listed by category at `wildscout.org/category/<slug>/`.
- Pages CMS edit link template: `https://app.pagescms.org/bbdevelop/wildscout-site/main/collection/posts/edit/{url-encoded-path}`, where `{url-encoded-path}` is the post's `file` value from `registry.json` (repo-root-relative, e.g. `src/content/blog/my-post.md`) with every `/` encoded as `%2F`. Include this link in the nightly Telegram summary for every finished draft article (see run-protocol.md).
- Publish policy: articles = draft only (agent never flips draft:true to false; human edits the frontmatter and pushes). Pages = draft only for now, same mechanism, until the user trusts the output; revisit later.

## Operational params (used by the engine's scripts)

- sitemapUrl: https://wildscout.org/sitemap-index.xml
- GSC property (siteUrl): sc-domain:wildscout.org (Domain property, verified via DNS TXT; the Search Console API needs this exact `sc-domain:` form, not a URL, for domain properties)
- GSC auth: service account, key at /home/bb/seo-agent-pack/secrets/gsc-service-account.json (Owner permission on the property), never printed or committed
- DataForSEO location: United States (location_code 2840), language: en
- IndexNow key: 27394fe1e8b2a7a5b57f54d3a3bfadbb66f5baf49a03468881aecdf3deb89921 (public by protocol design, not a secret; verification file lives at public/27394fe1e8b2a7a5b57f54d3a3bfadbb66f5baf49a03468881aecdf3deb89921.txt in the site repo, served at https://wildscout.org/27394fe1e8b2a7a5b57f54d3a3bfadbb66f5baf49a03468881aecdf3deb89921.txt)
- Pipeline type: local-files site. Image script writes into `public/images/blog/<slug>/` in the site repo, committed with the post and served by the static build.
- Image formats: AVIF for in-page section/featured images, WebP for the OG/hero copy image.
- Status file: /home/bb/seo-agent-pack/status/<YYYY-MM-DD>.txt (one line per run: `<site> | <job> | <result>`)
- Scripts directory: /home/bb/seo-agent-pack/scripts/
- .env location: /home/bb/seo-agent-pack/.env
