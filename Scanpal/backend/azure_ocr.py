# azure_ocr.py
import os
import re
from typing import Any, Dict, List, Optional
from datetime import datetime, timezone

from azure.core.credentials import AzureKeyCredential
from azure.ai.formrecognizer import DocumentAnalysisClient

# ----------------------------
# Numeric & small utils
# ----------------------------

def _num(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        # allow commas and $ for currency-y strings
        return float(str(v).replace(",", "").replace("$", "").strip())
    except Exception:
        return None

def _round2(x):
    return None if x is None else round(float(x) + 1e-8, 2)

def _strip_nones(d: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in d.items() if v is not None and v != ""}

def _iso_or_none(s: Optional[str]) -> Optional[str]:
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        return None

# ----------------------------
# Address helpers (unchanged)
# ----------------------------

def _address_to_dict(addr) -> dict:
    """Convert Azure AddressValue to a plain dict (JSON-safe)."""
    parts = {
        "house_number":   getattr(addr, "house_number",   None),
        "po_box":         getattr(addr, "po_box",         None),
        "road":           getattr(addr, "road",           None),
        "city":           getattr(addr, "city",           None),
        "state":          getattr(addr, "state",          None),
        "postal_code":    getattr(addr, "postal_code",    None),
        "country_region": getattr(addr, "country_region", None),
        "street_address": getattr(addr, "street_address", None),
        "unit":           getattr(addr, "unit",           None),
    }
    return _strip_nones(parts)

def _address_to_string(addr) -> str:
    """Make a readable single-line address from AddressValue."""
    d = _address_to_dict(addr)
    # prefer street_address if present
    core = d.get("street_address")
    if not core:
        hn   = d.get("house_number")
        road = d.get("road")
        unit = d.get("unit")
        core = " ".join(x for x in [hn, road] if x)
        if unit:
            core = f"{core}, {unit}" if core else unit
    tail = ", ".join(x for x in [d.get("city"), d.get("state"), d.get("postal_code"), d.get("country_region")] if x)
    return ", ".join(x for x in [core, tail] if x)

# ----------------------------
# Azure field reader (unchanged)
# ----------------------------

def _field_info(flds, name):
    """
    Returns (value, confidence, present_on_page).
    present_on_page=True if Azure mapped text/regions for that field.
    """
    fld = flds.get(name)
    if not fld:
        return None, 0.0, False

    # Prefer currency amount; else scalar/string value
    val = getattr(getattr(fld, "value_currency", None), "amount", None)
    if val is None:
        val = getattr(fld, "value", None)

    conf = float(getattr(fld, "confidence", 0.0) or 0.0)

    content = getattr(fld, "content", None)
    regions = getattr(fld, "bounding_regions", None)
    present = bool((content and str(content).strip()) or (regions and len(regions) > 0))
    return val, conf, present

# ----------------------------
# Tax extraction helpers
# ----------------------------

# Match currency-ish numbers like "$10.44" or "10.44"
_NUM_RE = re.compile(r"[-+]?\$?\s*(\d{1,3}(?:,\d{3})*|\d+)(?:\.(\d{2}))?")

# Keywords we accept as "tax" field names
_TAX_KEYS = {
    "tax", "sales tax", "sale tax", "state tax", "city tax", "total tax",
    "hst", "gst", "pst", "vat"
}

def _maybe_extract_tax_from_fields_dict(fields: Dict[str, Any]) -> Optional[float]:
    """
    If you have a raw dict of fields (not Azure Field objects), scan for known tax-like keys.
    """
    for k, v in fields.items():
        lk = str(k).strip().lower()
        if lk in _TAX_KEYS or lk in {"total_tax", "grand_total_tax", "sales_tax"}:
            val = _num(v)
            if val is not None:
                return _round2(val)
    return None

def _maybe_extract_tax_from_lines(lines: List[str]) -> Optional[float]:
    """
    Look for a line mentioning 'tax' and take the last number on that line.
    Avoid false positives like 'taxable'.
    """
    for line in lines:
        l = line.strip()
        ll = l.lower()
        if "tax" not in ll:
            continue
        # skip "taxable", "pre-tax" etc. keep "sales tax", "state tax"
        if "taxable" in ll:
            continue
        # Extract last numeric on the line
        nums = list(_NUM_RE.finditer(l))
        if not nums:
            continue
        g = nums[-1]
        whole = g.group(1)
        cents = g.group(2) or "00"
        try:
            return _round2(float(f"{whole.replace(',','')}.{cents}"))
        except Exception:
            pass
    return None

def _plausible_tax(subtotal: Optional[float], total: Optional[float]) -> Optional[float]:
    """
    Infer tax as total - subtotal, but only when plausible: 0.5%–15% of subtotal and > $0.01.
    """
    if subtotal is None or total is None:
        return None
    cand = _round2(total - subtotal)
    if cand is None or cand <= 0.01:
        return None
    if subtotal > 0:
        pct = cand / subtotal
        if 0.005 <= pct <= 0.15:
            return cand
    return None

# ----------------------------
# Main entry
# ----------------------------

def analyze_receipt_azure(image_bytes: bytes) -> Dict[str, Any]:
    endpoint = os.environ["AZURE_DOCINT_ENDPOINT"]
    key = os.environ["AZURE_DOCINT_KEY"]

    client = DocumentAnalysisClient(endpoint, AzureKeyCredential(key))
    poller = client.begin_analyze_document("prebuilt-receipt", document=image_bytes)
    result = poller.result()

    if not result.documents:
        raise RuntimeError("No receipt detected")

    doc = result.documents[0]
    f = doc.fields or {}

    merchant, c_merchant, _ = _field_info(f, "MerchantName")
    addr_val, c_addr, _      = _field_info(f, "MerchantAddress")
    date, c_date, _          = _field_info(f, "TransactionDate")

    subtotal_val, c_sub, p_sub = _field_info(f, "Subtotal")
    tax_val, c_tax, p_tax      = _field_info(f, "Tax")
    # tip intentionally ignored
    total_val, c_total, _      = _field_info(f, "Total")

    # Collect OCR lines (for tax fallback like "Sales Tax .... $10.44")
    lines: List[str] = []
    try:
        for p in (result.pages or []):
            for ln in (p.lines or []):
                if ln and getattr(ln, "content", None):
                    lines.append(str(ln.content))
    except Exception:
        pass

    # Flatten address safely
    address_text = None
    address_components = None
    if addr_val is not None:
        try:
            address_text = _address_to_string(addr_val)
            address_components = _address_to_dict(addr_val)
        except Exception:
            address_text = str(addr_val)

    # Items
    items_out: List[Dict[str, Any]] = []
    items_fld = f.get("Items")
    if items_fld and getattr(items_fld, "value", None):
        for it in items_fld.value:
            obj = it.value or {}

            def grab(objname):
                fld = obj.get(objname)
                if not fld:
                    return None
                val = getattr(getattr(fld, "value_currency", None), "amount", None)
                if val is None:
                    val = getattr(fld, "value", None)
                return val

            items_out.append({
                "name":       (obj.get("Description").value if obj.get("Description") else None),
                "quantity":   _num(grab("Quantity")),
                "unit_price": _num(grab("Price")),
                "total":      _num(grab("TotalPrice")),
            })

    subtotal_num = _num(subtotal_val)
    total_num    = _num(total_val)

    # --------------------
    # Robust Tax Logic
    # --------------------
    tax_num: Optional[float] = None

    # 1) Trust Azure field when present & minimally confident
    if p_tax and c_tax >= 0.60 and tax_val is not None:
        t = _num(tax_val)
        if t is not None and abs(t) > 1e-6:
            tax_num = _round2(t)

    # 2) OCR line fallback — catches "Sales Tax", "State Tax", etc.
    if tax_num is None and lines:
        tax_num = _maybe_extract_tax_from_lines(lines)

    # 3) Fallback math (no tip): total - subtotal, but only if plausible
    if tax_num is None:
        tax_num = _plausible_tax(subtotal_num, total_num)

    # Base payload
    payload: Dict[str, Any] = {
        "provider": "azure",
        "merchant": merchant,
        "address": address_text,                          # JSON-safe string
        "date": _iso_or_none(str(date)) if date else None,
        "total": _round2(total_num),
        "items": items_out,
        "confidences": {
            "merchant": c_merchant,
            "address": c_addr,
            "date": c_date,
            "subtotal": c_sub,
            "tax": c_tax,
            "total": c_total,
        }
    }
    if address_components:
        payload["address_components"] = address_components  # optional structured address

    # Include only if present & confident
    if p_sub and c_sub >= 0.80 and subtotal_num is not None:
        payload["subtotal"] = _round2(subtotal_num)

    # Include tax only if we truly found/plausibly inferred it
    if tax_num is not None:
        payload["tax"] = _round2(tax_num)

    # TIP: do not include at all (you said you don't use tips)

    # Drop None keys 
    payload["raw_lines"] = lines 

    return {k: v for k, v in payload.items() if v is not None}
