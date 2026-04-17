"""Supabase Storage wrapper using direct HTTP calls (no SDK needed)."""
import os
import logging
import requests

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "")
BUCKET = "scanpal-uploads"


def _headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
    }


def upload_file(filename: str, data: bytes, content_type: str = "application/octet-stream") -> str:
    """Upload a file to Supabase Storage. Returns the public URL."""
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{filename}"
    headers = _headers()
    headers["Content-Type"] = content_type
    headers["x-upsert"] = "true"
    resp = requests.post(url, headers=headers, data=data)
    resp.raise_for_status()
    return get_public_url(filename)


def get_public_url(filename: str) -> str:
    """Get the public URL for a file in the bucket."""
    return f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{filename}"


def download_file(filename: str) -> bytes:
    """Download a file from Supabase Storage."""
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{filename}"
    resp = requests.get(url, headers=_headers())
    resp.raise_for_status()
    return resp.content


def delete_file(filename: str):
    """Delete a file from Supabase Storage. Silently ignores missing files."""
    try:
        url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}"
        resp = requests.delete(url, headers={**_headers(), "Content-Type": "application/json"}, json={"prefixes": [filename]})
    except Exception as e:
        logging.warning(f"Failed to delete {filename} from storage: {e}")


def delete_files(filenames: list):
    """Delete multiple files from Supabase Storage."""
    if not filenames:
        return
    try:
        url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}"
        resp = requests.delete(url, headers={**_headers(), "Content-Type": "application/json"}, json={"prefixes": filenames})
    except Exception as e:
        logging.warning(f"Failed to delete files from storage: {e}")
