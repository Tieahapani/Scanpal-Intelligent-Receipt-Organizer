import os
import re
import logging
import requests
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

UNSPLASH_ACCESS_KEY = os.getenv("UNSPLASH_ACCESS_KEY")
UNSPLASH_API_URL = "https://api.unsplash.com/search/photos"

# US state abbreviations to strip from destination strings
_STATE_ABBREVS = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
}


def _clean_destination(raw: str) -> str:
    """Extract a clean city/place name from messy destination strings.
    Handles formats like 'Hayward,CA', 'Long Beach Trip', 'SJSU',
    '1001 Broadway, Oakland, California 94607', etc."""
    text = raw.strip()

    # Remove "Trip" suffix (case-insensitive)
    text = re.sub(r'\s*trip\s*$', '', text, flags=re.IGNORECASE)

    # Remove zip codes
    text = re.sub(r'\b\d{5}(-\d{4})?\b', '', text)

    # Remove street numbers at the start (e.g. "1001 Broadway, Oakland...")
    text = re.sub(r'^\d+\s+\w+\s*(,|\.)\s*', '', text)

    # Remove state abbreviations (standalone, after comma, etc.)
    parts = [p.strip() for p in text.split(',')]
    cleaned_parts = []
    for part in parts:
        words = part.split()
        filtered = [w for w in words if w.upper() not in _STATE_ABBREVS]
        joined = ' '.join(filtered).strip()
        if joined:
            cleaned_parts.append(joined)
    text = ', '.join(cleaned_parts)

    # Remove full state names like "California"
    text = re.sub(r',?\s*\b(California|Texas|Florida|New York|Illinois|Ohio|Pennsylvania|Georgia|Michigan|Washington)\b', '', text, flags=re.IGNORECASE)

    return text.strip().strip(',').strip()


def _search_unsplash(query: str) -> str | None:
    """Run a single Unsplash search, return image URL or None."""
    resp = requests.get(
        UNSPLASH_API_URL,
        params={
            "query": query,
            "per_page": 1,
            "orientation": "landscape",
        },
        headers={"Authorization": f"Client-ID {UNSPLASH_ACCESS_KEY}"},
        timeout=10,
    )
    resp.raise_for_status()
    results = resp.json().get("results", [])
    if results:
        return results[0]["urls"]["regular"]
    return None


def fetch_destination_image(destination: str) -> str | None:
    """Fetch a landscape photo URL from Unsplash for the given destination.
    Tries progressively broader queries to handle small cities and typos.
    Returns the regular-size image URL, or None on failure."""
    if not UNSPLASH_ACCESS_KEY:
        logger.warning("UNSPLASH_ACCESS_KEY not set, skipping image fetch")
        return None

    if not destination or not destination.strip():
        return None

    city = _clean_destination(destination)
    if not city:
        city = destination.strip()

    # Try queries from most specific to broadest
    queries = [
        f"{city} city landmark",
        f"{city} travel",
        city,
    ]

    try:
        for query in queries:
            url = _search_unsplash(query)
            if url:
                logger.info(f"Unsplash hit for '{destination}' using query '{query}'")
                return url
        logger.info(f"No Unsplash results for '{destination}' (tried {len(queries)} queries)")
        return None
    except Exception as e:
        logger.error(f"Unsplash fetch failed for '{destination}': {e}")
        return None
