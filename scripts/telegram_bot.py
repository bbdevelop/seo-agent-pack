#!/usr/bin/env python3
"""
Telegram notify client. Auth via TELEGRAM_BOT_TOKEN env var, never printed.

Usage:
  python3 telegram_bot.py find-chat-id
  python3 telegram_bot.py send <chat_id> "<message text>"
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://api.telegram.org"


def _token():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        sys.exit("TELEGRAM_BOT_TOKEN is not set. source your .env first.")
    return token


def _get(method, params=None):
    url = f"{API_BASE}/bot{_token()}/{method}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"Telegram HTTP {e.code}: {e.read().decode()}")


def find_chat_ids():
    data = _get("getUpdates")
    chats = {}
    for update in data.get("result", []):
        msg = update.get("message") or update.get("channel_post")
        if not msg:
            continue
        chat = msg["chat"]
        chats[chat["id"]] = {
            "type": chat.get("type"),
            "name": chat.get("username") or chat.get("first_name") or chat.get("title"),
            "last_text": msg.get("text"),
        }
    return chats


def send_message(chat_id, text):
    data = urllib.parse.urlencode({"chat_id": chat_id, "text": text}).encode()
    req = urllib.request.Request(
        f"{API_BASE}/bot{_token()}/sendMessage", data=data, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"Telegram HTTP {e.code}: {e.read().decode()}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "find-chat-id":
        print(json.dumps(find_chat_ids(), indent=2))
    elif cmd == "send":
        if len(sys.argv) < 4:
            sys.exit("Usage: telegram_bot.py send <chat_id> \"<text>\"")
        result = send_message(sys.argv[2], sys.argv[3])
        print(json.dumps({"ok": result.get("ok"), "message_id": result.get("result", {}).get("message_id")}, indent=2))
    else:
        sys.exit(f"Unknown command: {cmd}")
