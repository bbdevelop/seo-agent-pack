#!/usr/bin/env python3
"""
Daily/weekly auto-indexing: reads the sitemap, submits new/updated published
URLs to Google (Indexing API) and Bing (IndexNow), and once a week resubmits
the sitemap and reports what is still not indexed.

Site params come from a JSON sidecar (see sites/<domain>.json), not CLI flags,
so a cron job can call this with a single fixed argument.

Usage:
  python3 auto_index.py daily <site_json_path>
  python3 auto_index.py weekly <site_json_path>
"""
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gsc_query  # noqa: E402  (reuses the service-account JWT auth)

NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}


def _fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "wildscout-seo-agent/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def get_sitemap_urls(sitemap_url, _depth=0):
    if _depth > 3:
        return []
    root = ET.fromstring(_fetch(sitemap_url))
    tag = root.tag.split("}")[-1]
    urls = []
    if tag == "sitemapindex":
        for sm in root.findall("sm:sitemap", NS):
            loc = sm.findtext("sm:loc", namespaces=NS)
            if loc:
                urls.extend(get_sitemap_urls(loc, _depth + 1))
    elif tag == "urlset":
        for u in root.findall("sm:url", NS):
            loc = u.findtext("sm:loc", namespaces=NS)
            lastmod = u.findtext("sm:lastmod", namespaces=NS)
            if loc:
                urls.append({"loc": loc, "lastmod": lastmod})
    return urls


def load_registry(registry_path):
    if not os.path.exists(registry_path):
        return []
    with open(registry_path) as f:
        return json.load(f).get("posts", [])


def load_state(state_path):
    if os.path.exists(state_path):
        with open(state_path) as f:
            return json.load(f)
    return {}


def save_state(state_path, state):
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    with open(state_path, "w") as f:
        json.dump(state, f, indent=2)


def submit_google_indexing(url, access_token):
    req = urllib.request.Request(
        "https://indexing.googleapis.com/v3/urlNotifications:publish",
        data=json.dumps({"url": url, "type": "URL_UPDATED"}).encode(),
        headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return True, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return False, e.read().decode()


def submit_bing_indexnow(urls, host, key, key_location):
    payload = {"host": host, "key": key, "keyLocation": key_location, "urlList": urls}
    req = urllib.request.Request(
        "https://api.indexnow.org/indexnow",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return True, resp.status
    except urllib.error.HTTPError as e:
        return False, f"{e.code}: {e.read().decode()}"


def submit_sitemap(gsc_site_url, sitemap_url, access_token):
    endpoint = (
        f"https://www.googleapis.com/webmasters/v3/sites/{urllib.parse.quote(gsc_site_url, safe='')}"
        f"/sitemaps/{urllib.parse.quote(sitemap_url, safe='')}"
    )
    req = urllib.request.Request(endpoint, data=b"", headers={"Authorization": f"Bearer {access_token}"}, method="PUT")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return True, resp.status
    except urllib.error.HTTPError as e:
        return False, f"{e.code}: {e.read().decode()}"


def inspect_url(gsc_site_url, url, access_token):
    req = urllib.request.Request(
        "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect",
        data=json.dumps({"inspectionUrl": url, "siteUrl": gsc_site_url}).encode(),
        headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": f"{e.code}: {e.read().decode()}"}
    result = data.get("inspectionResult", {}).get("indexStatusResult", {})
    return {"coverageState": result.get("coverageState"), "verdict": result.get("verdict")}


def load_site(site_json_path):
    with open(site_json_path) as f:
        return json.load(f)


def _auth(site):
    os.environ["GSC_KEY_PATH"] = site["gscKeyPath"]
    key_data = gsc_query._load_key()
    return gsc_query._get_access_token(key_data)


def cmd_daily(site):
    access_token = _auth(site)

    sitemap_urls = {u["loc"] for u in get_sitemap_urls(site["sitemapUrl"])}
    registry = load_registry(site["registryPath"])
    registry_dates = {}
    for post in registry:
        if post.get("status") != "published":
            continue
        slug = post.get("slug")
        url = f"https://{site['domain']}/blog/{slug}/"
        registry_dates[url] = post.get("updatedDate") or post.get("pubDate")

    state_path = os.path.join(site["statusDir"], f"index-state-{site['domain']}.json")
    state = load_state(state_path)

    to_submit = []
    for url in sitemap_urls:
        current_date = registry_dates.get(url)
        prev_date = state.get(url)
        if url not in state or (current_date and current_date != prev_date):
            to_submit.append(url)

    results = {"checked": len(sitemap_urls), "submitted": [], "google_errors": [], "bing": None}
    for url in to_submit:
        ok, resp = submit_google_indexing(url, access_token)
        if ok:
            # Only mark done on success, so a failed submission gets retried tomorrow
            # instead of silently being treated as handled.
            state[url] = registry_dates.get(url, datetime.date.today().isoformat())
            results["submitted"].append(url)
        else:
            results["google_errors"].append({"url": url, "error": resp})

    if to_submit:
        ok, resp = submit_bing_indexnow(
            to_submit, site["indexNowHost"], site["indexNowKey"], site["indexNowKeyLocation"],
        )
        results["bing"] = {"ok": ok, "detail": resp}

    save_state(state_path, state)
    return results


def cmd_weekly(site):
    access_token = _auth(site)

    ok, resp = submit_sitemap(site["gscSiteUrl"], site["sitemapUrl"], access_token)

    sitemap_urls = [u["loc"] for u in get_sitemap_urls(site["sitemapUrl"])]
    not_indexed = []
    for url in sitemap_urls:
        result = inspect_url(site["gscSiteUrl"], url, access_token)
        coverage = (result.get("coverageState") or "")
        if result.get("error"):
            not_indexed.append({"url": url, "error": result["error"]})
        elif "submitted and indexed" not in coverage.lower():
            not_indexed.append({"url": url, "coverageState": coverage, "verdict": result.get("verdict")})
        time.sleep(1)  # be polite to the API

    report = {
        "sitemap_submit": {"ok": ok, "detail": resp},
        "total_urls": len(sitemap_urls),
        "not_indexed": not_indexed,
    }

    report_path = os.path.join(
        site["statusDir"], f"not-indexed-{site['domain']}-{datetime.date.today().isoformat()}.txt",
    )
    os.makedirs(site["statusDir"], exist_ok=True)
    with open(report_path, "w") as f:
        f.write(f"{site['domain']} weekly indexing report - {datetime.date.today().isoformat()}\n")
        f.write(f"Sitemap resubmitted: {'OK' if ok else 'FAILED - ' + str(resp)}\n")
        f.write(f"Total URLs in sitemap: {len(sitemap_urls)}\n")
        f.write(f"Not indexed / needs attention: {len(not_indexed)}\n\n")
        for item in not_indexed:
            f.write(f"- {item['url']}: {item.get('coverageState') or item.get('error')}\n")
    report["report_file"] = report_path
    return report


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mode, site_path = sys.argv[1], sys.argv[2]
    site = load_site(site_path)
    if mode == "daily":
        out = cmd_daily(site)
    elif mode == "weekly":
        out = cmd_weekly(site)
    else:
        sys.exit(f"Unknown mode: {mode}")
    print(json.dumps(out, indent=2))
