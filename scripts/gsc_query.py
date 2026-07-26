#!/usr/bin/env python3
"""
Google Search Console query client, authenticated as a service account.
No third-party libraries: signs its own JWT via the system `openssl` binary,
exchanges it for an access token, then calls the searchAnalytics.query REST API.

The key file path comes from GSC_KEY_PATH (default: secrets/gsc-service-account.json
next to this script's repo root). Its contents are never printed.

Usage:
  python3 gsc_query.py <site_url> [start_date] [end_date] [dimensions_csv] [row_limit]

  site_url    e.g. sc-domain:wildscout.org (domain property) or https://example.com/ (URL-prefix)
  start_date  YYYY-MM-DD, default: 30 days ago
  end_date    YYYY-MM-DD, default: 3 days ago (GSC data lags a few days)
  dimensions  csv, default: query
  row_limit   default: 25
"""
import base64
import datetime
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_KEY_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "secrets", "gsc-service-account.json",
)
SCOPES = [
    "https://www.googleapis.com/auth/webmasters",
    "https://www.googleapis.com/auth/indexing",
]


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _load_key():
    path = os.environ.get("GSC_KEY_PATH", DEFAULT_KEY_PATH)
    if not os.path.exists(path):
        sys.exit(f"Service account key not found at {path}")
    with open(path) as f:
        return json.load(f)


def _get_access_token(key_data):
    now = int(datetime.datetime.now().timestamp())
    header = {"alg": "RS256", "typ": "JWT"}
    claims = {
        "iss": key_data["client_email"],
        "scope": " ".join(SCOPES),
        "aud": key_data.get("token_uri", "https://oauth2.googleapis.com/token"),
        "iat": now,
        "exp": now + 3600,
    }
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64url(json.dumps(claims, separators=(",", ":")).encode())
    )

    keyfile_fd, keyfile_path = tempfile.mkstemp(suffix=".pem")
    try:
        with os.fdopen(keyfile_fd, "w") as kf:
            kf.write(key_data["private_key"])
        os.chmod(keyfile_path, 0o600)
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", keyfile_path],
            input=signing_input.encode(),
            capture_output=True,
            check=True,
        )
    finally:
        os.unlink(keyfile_path)

    jwt = f"{signing_input}.{_b64url(proc.stdout)}"
    data = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": jwt,
    }).encode()
    req = urllib.request.Request(
        key_data.get("token_uri", "https://oauth2.googleapis.com/token"),
        data=data, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())["access_token"]
    except urllib.error.HTTPError as e:
        sys.exit(f"Token exchange HTTP {e.code}: {e.read().decode()}")


def query_search_analytics(site_url, access_token, start_date, end_date,
                            dimensions=None, row_limit=25):
    dimensions = dimensions or ["query"]
    endpoint = (
        "https://www.googleapis.com/webmasters/v3/sites/"
        f"{urllib.parse.quote(site_url, safe='')}/searchAnalytics/query"
    )
    payload = {
        "startDate": start_date,
        "endDate": end_date,
        "dimensions": dimensions,
        "rowLimit": row_limit,
    }
    req = urllib.request.Request(
        endpoint, data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"GSC HTTP {e.code}: {e.read().decode()}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    site_url = sys.argv[1]
    today = datetime.date.today()
    start_date = sys.argv[2] if len(sys.argv) > 2 else str(today - datetime.timedelta(days=30))
    end_date = sys.argv[3] if len(sys.argv) > 3 else str(today - datetime.timedelta(days=3))
    dimensions = sys.argv[4].split(",") if len(sys.argv) > 4 else ["query"]
    row_limit = int(sys.argv[5]) if len(sys.argv) > 5 else 25

    key_data = _load_key()
    token = _get_access_token(key_data)
    result = query_search_analytics(site_url, token, start_date, end_date, dimensions, row_limit)
    print(json.dumps(result, indent=2))
