#!/usr/bin/env python3
"""
DataForSEO keyword client: volume, CPC, difficulty, intent, and suggestions.
Auth comes from the DATAFORSEO_AUTH env var (never printed, never logged).

Usage:
  python3 dataforseo_keywords.py overview "backpacking tent" "4 person tent"
  python3 dataforseo_keywords.py suggestions "backpacking tent" [limit]
"""
import base64
import json
import os
import sys
import urllib.request
import urllib.error

API_BASE = "https://api.dataforseo.com/v3"
LOCATION_CODE = 2840  # United States
LANGUAGE_CODE = "en"


def _auth_header():
    auth = os.environ.get("DATAFORSEO_AUTH")
    if not auth:
        sys.exit("DATAFORSEO_AUTH is not set. source your .env first.")
    if ":" in auth:
        token = base64.b64encode(auth.encode()).decode()
    else:
        token = auth
    return f"Basic {token}"


def _post(path, payload):
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": _auth_header(),
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        sys.exit(f"DataForSEO HTTP {e.code}: {body}")


def keyword_overview(keywords):
    payload = [{
        "keywords": keywords,
        "location_code": LOCATION_CODE,
        "language_code": LANGUAGE_CODE,
    }]
    data = _post("/dataforseo_labs/google/keyword_overview/live", payload)
    results = []
    for task in data.get("tasks", []):
        for result in (task.get("result") or []):
            for item in (result.get("items") or []):
                info = item.get("keyword_info") or {}
                kd = item.get("keyword_properties") or {}
                intent = item.get("search_intent_info") or {}
                results.append({
                    "keyword": item.get("keyword"),
                    "search_volume": info.get("search_volume"),
                    "cpc": info.get("cpc"),
                    "competition": info.get("competition"),
                    "keyword_difficulty": kd.get("keyword_difficulty"),
                    "search_intent": intent.get("main_intent"),
                })
    return results


def keyword_suggestions(seed, limit=20):
    payload = [{
        "keyword": seed,
        "location_code": LOCATION_CODE,
        "language_code": LANGUAGE_CODE,
        "limit": limit,
        "include_seed_keyword": False,
    }]
    data = _post("/dataforseo_labs/google/keyword_suggestions/live", payload)
    results = []
    for task in data.get("tasks", []):
        for result in (task.get("result") or []):
            for item in (result.get("items") or []):
                info = item.get("keyword_info") or {}
                kd = item.get("keyword_properties") or {}
                results.append({
                    "keyword": item.get("keyword"),
                    "search_volume": info.get("search_volume"),
                    "cpc": info.get("cpc"),
                    "keyword_difficulty": kd.get("keyword_difficulty"),
                })
    results.sort(key=lambda r: (r["search_volume"] or 0), reverse=True)
    return results


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "overview":
        out = keyword_overview(sys.argv[2:])
    elif cmd == "suggestions":
        seed = sys.argv[2]
        limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20
        out = keyword_suggestions(seed, limit)
    else:
        sys.exit(f"Unknown command: {cmd}")
    print(json.dumps(out, indent=2))
