#!/usr/bin/env python3
"""
Gemini image generation, following skills/seo-engine/references/image-prompts.md:
one exhaustive prompt in, one AVIF (in-page) + one WebP (OG) out.

Auth: GEMINI_API_KEY env var, sent as the x-goog-api-key header. Never printed.

Usage:
  python3 gemini_image.py <prompt_file_or_-> <output_dir> <slug> [aspect_ratio]

  prompt_file_or_-  path to a text file holding the full 500-800 word prompt, or
                    '-' to read the prompt from stdin
  output_dir        directory to write <slug>.avif and <slug>.webp into
  slug              keyword-slug filename base, e.g. best-backpacking-tent-2026
  aspect_ratio      default 16:9 (image-prompts.md: landscape 16:9 always)
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

API_URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
MODEL = "gemini-3.1-flash-image"


def generate_image(prompt, aspect_ratio="16:9", image_size="2K"):
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        sys.exit("GEMINI_API_KEY is not set. source your .env first.")

    payload = {
        "model": MODEL,
        "input": [{"type": "text", "text": prompt}],
        "response_format": {
            "type": "image",
            "mime_type": "image/jpeg",
            "aspect_ratio": aspect_ratio,
            "image_size": image_size,
        },
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode(),
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"Gemini HTTP {e.code}: {e.read().decode()}")

    # The raw REST response nests images in steps[].content[] (type == "image").
    # "output_image" is only a client-SDK convenience property, not present here.
    for step in data.get("steps", []):
        for block in step.get("content", []):
            if block.get("type") == "image" and block.get("data"):
                return base64.b64decode(block["data"])
    sys.exit(f"No image in response. status={data.get('status')} steps_types="
              f"{[s.get('type') for s in data.get('steps', [])]}")


def save_as_avif_and_webp(png_bytes, output_dir, slug):
    os.makedirs(output_dir, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
        f.write(png_bytes)
        tmp_png = f.name

    avif_path = os.path.join(output_dir, f"{slug}.avif")
    webp_path = os.path.join(output_dir, f"{slug}.webp")
    try:
        subprocess.run(["convert", tmp_png, avif_path], check=True, capture_output=True)
        subprocess.run(["convert", tmp_png, webp_path], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        sys.exit(f"convert failed: {e.stderr.decode()}")
    finally:
        os.unlink(tmp_png)
    return avif_path, webp_path


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    prompt_arg, output_dir, slug = sys.argv[1], sys.argv[2], sys.argv[3]
    aspect_ratio = sys.argv[4] if len(sys.argv) > 4 else "16:9"

    if prompt_arg == "-":
        prompt = sys.stdin.read()
    else:
        with open(prompt_arg) as f:
            prompt = f.read()

    word_count = len(prompt.split())
    if word_count < 500:
        print(f"WARNING: prompt is {word_count} words, under the 500-word hard floor.", file=sys.stderr)

    png_bytes = generate_image(prompt, aspect_ratio)
    avif_path, webp_path = save_as_avif_and_webp(png_bytes, output_dir, slug)

    print(json.dumps({
        "avif": avif_path,
        "avif_bytes": os.path.getsize(avif_path),
        "webp": webp_path,
        "webp_bytes": os.path.getsize(webp_path),
        "prompt_words": word_count,
    }, indent=2))
