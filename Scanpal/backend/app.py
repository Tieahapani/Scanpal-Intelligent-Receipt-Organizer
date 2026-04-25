import os
import logging
import json
import uuid
import secrets
import bcrypt
import threading
import time
import random
from datetime import datetime, timezone, timedelta

from flask import Flask, request, jsonify, g, Response
from dotenv import load_dotenv
from flask_cors import CORS
import google.generativeai as genai
import google.api_core.exceptions


from models import SessionLocal, User, Trip, Receipt, OtpCode, Alert, PendingReview, init_db, engine
from notion_service import NotionService
from auth import create_token, decode_token, require_auth, require_admin, is_admin_email, ADMIN_EMAILS, JWT_SECRET, JWT_ALGORITHM
import jwt
from azure_ocr import analyze_receipt_azure
from email_utils import send_otp_email
from unsplash import fetch_destination_image
from storage import upload_file, download_file, delete_file, delete_files, get_public_url

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app)

logging.basicConfig(level=logging.INFO)

init_db()

# Add password_hash column if missing (migration for existing DBs)
from sqlalchemy import inspect as sa_inspect, or_ as db_or, text as sa_text, func as sa_func
with engine.connect() as conn:
    cols = [c["name"] for c in sa_inspect(engine).get_columns("users")]
    if "password_hash" not in cols:
        conn.execute(sa_text("ALTER TABLE users ADD COLUMN password_hash VARCHAR"))
        conn.commit()
        logging.info("Added password_hash column to users table")
    if "remembered" not in cols:
        conn.execute(sa_text("ALTER TABLE users ADD COLUMN remembered BOOLEAN DEFAULT FALSE"))
        conn.commit()
        logging.info("Added remembered column to users table")

    otp_cols = [c["name"] for c in sa_inspect(engine).get_columns("otp_codes")]
    if "pending_password" not in otp_cols:
        conn.execute(sa_text("ALTER TABLE otp_codes ADD COLUMN pending_password VARCHAR"))
        conn.commit()
        logging.info("Added pending_password column to otp_codes table")

    trip_cols = [c["name"] for c in sa_inspect(engine).get_columns("trips")]
    if "cover_image_url" not in trip_cols:
        conn.execute(sa_text("ALTER TABLE trips ADD COLUMN cover_image_url TEXT"))
        conn.commit()
        logging.info("Added cover_image_url column to trips table")

    receipt_cols = [c["name"] for c in sa_inspect(engine).get_columns("receipts")]
    if "payment_method" not in receipt_cols:
        conn.execute(sa_text("ALTER TABLE receipts ADD COLUMN payment_method VARCHAR(20) DEFAULT 'personal'"))
        conn.commit()
        logging.info("Added payment_method column to receipts table")

# Configure Gemini
genai.configure(api_key=os.environ["GEMINI_API_KEY"])


# ─── Gemini Rate Limiter & Retry Logic (Google ADK pattern) ──────────────
class GeminiRateLimiter:
    """Token bucket rate limiter to smooth Gemini API traffic."""

    def __init__(self, requests_per_minute=15, burst=5):
        self._rate = requests_per_minute / 60.0  # tokens per second
        self._max_tokens = burst
        self._tokens = float(burst)
        self._last_refill = time.monotonic()
        self._lock = threading.Lock()

    def acquire(self, timeout=30):
        """Block until a token is available or timeout is reached."""
        deadline = time.monotonic() + timeout
        while True:
            with self._lock:
                now = time.monotonic()
                elapsed = now - self._last_refill
                self._tokens = min(self._max_tokens, self._tokens + elapsed * self._rate)
                self._last_refill = now
                if self._tokens >= 1.0:
                    self._tokens -= 1.0
                    return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.1)


_gemini_limiter = GeminiRateLimiter(
    requests_per_minute=int(os.environ.get("GEMINI_RPM", 15)),
    burst=int(os.environ.get("GEMINI_BURST", 5)),
)


def gemini_call_with_retry(model, content, generation_config=None,
                           max_retries=5, initial_delay=4.0, max_delay=60.0):
    """Call Gemini with exponential backoff, jitter, and rate limiting.

    Each attempt (including retries) acquires a rate limiter token first,
    so retries are properly spaced at the configured RPM.
    - Initial delay: 4s (safe for 15 RPM = 1 req every 4s)
    - Full jitter: random(delay/2, delay) to avoid thundering herd
    - Retries on 429 (ResourceExhausted) and 503 (ServiceUnavailable)
    """
    delay = initial_delay
    last_err = None

    for attempt in range(max_retries):
        if not _gemini_limiter.acquire(timeout=60):
            raise Exception("Rate limit queue timeout — too many concurrent requests")
        try:
            kwargs = {"generation_config": generation_config} if generation_config else {}
            response = model.generate_content(content, **kwargs)
            logging.info(f"Gemini call SUCCESS (attempt {attempt + 1}/{max_retries})")
            return response
        except google.api_core.exceptions.ResourceExhausted as e:
            last_err = e
            jittered = random.uniform(delay / 2, delay)
            logging.warning(
                f"Gemini 429, retry {attempt + 1}/{max_retries} in {jittered:.1f}s "
                f"(base delay {delay:.0f}s)"
            )
            time.sleep(jittered)
            delay = min(delay * 2, max_delay)
        except google.api_core.exceptions.ServiceUnavailable as e:
            last_err = e
            jittered = random.uniform(delay / 2, delay)
            logging.warning(
                f"Gemini 503, retry {attempt + 1}/{max_retries} in {jittered:.1f}s"
            )
            time.sleep(jittered)
            delay = min(delay * 2, max_delay)
        except Exception:
            raise

    logging.error(f"Gemini exhausted after {max_retries} retries: {last_err}")
    raise last_err


# Initialize Notion service
notion = NotionService()

# Travel-specific expense categories
TRAVEL_CATEGORIES = [
    "Accommodation Cost",
    "Flight Cost",
    "Ground Transportation",
    "Registration Cost",
    "Meals",
    "Other AS Cost",
]

# File storage is handled by Supabase Storage (see storage.py)


# =============================================================================
# HEALTH CHECK
# =============================================================================

@app.get("/health")
def health():
    return {"status": "ok", "provider": "azure"}, 200


@app.get("/departments")
def get_departments():
    """Return the list of department options from Notion's select field."""
    try:
        notion = NotionService()
        departments = notion.get_department_options()
        return jsonify(departments), 200
    except Exception as e:
        logging.error(f"Failed to fetch departments: {e}")
        return jsonify({"error": "Failed to fetch departments"}), 500


# =============================================================================
# AUTH
# =============================================================================

OTP_EXPIRY_MINUTES = 5
OTP_MAX_ATTEMPTS = 5


@app.post("/auth/login")
def login():
    """Step 1: validate email + optional password, or send OTP."""
    data = request.get_json()
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    remember_me = data.get("remember_me", False)

    if not email:
        return jsonify({"error": "Email is required"}), 400

    db = SessionLocal()
    try:
        # Clean up expired OTPs
        cutoff = datetime.utcnow() - timedelta(minutes=OTP_EXPIRY_MINUTES)
        db.query(OtpCode).filter(OtpCode.created_at < cutoff).delete()

        user = db.query(User).filter(User.email == email).first()

        # --- Password login (if user exists and has a password set) ---
        if user and user.password_hash and password:
            if not bcrypt.checkpw(password.encode("utf-8"), user.password_hash.encode("utf-8")):
                return jsonify({"error": "Incorrect password"}), 401

            # Password correct — check if user is remembered (skip OTP)
            if user.remembered:
                user.role = "admin" if is_admin_email(email) else user.role
                try:
                    _sync_trips_from_notion(db, email)
                except Exception as sync_err:
                    logging.error(f"Trip sync on password login failed: {sync_err}")
                db.commit()

                token = create_token(user.id, user.email, user.role)
                return jsonify({
                    "token": token,
                    "user": user.to_dict(),
                }), 200

            # Password correct but not remembered — still need OTP
            # Fall through to OTP flow below

        # --- OTP flow (no password provided, no password set yet, or password correct but not remembered) ---
        if not user:
            notion_rows = notion.get_rows_by_email(email)
            if notion_rows:
                # Found in Notion — will create user after OTP verification
                parsed = notion.parse_notion_row(notion_rows[0])
                purpose = "login"
                otp_name = parsed.get("traveler_name") or email.split("@")[0]
                otp_dept = parsed.get("department")
            else:
                # Not found anywhere
                if is_admin_email(email):
                    # Admin emails can proceed without Notion data
                    purpose = "login"
                    otp_name = email.split("@")[0]
                    otp_dept = None
                else:
                    # Check if registration data was provided
                    name = (data.get("name") or "").strip()
                    if not name:
                        return jsonify({"needs_registration": True}), 200

                    purpose = "register"
                    otp_name = name
                    otp_dept = (data.get("department") or "").strip() or None
        else:
            purpose = "login"
            otp_name = None
            otp_dept = None

        # Invalidate any existing OTPs for this email
        db.query(OtpCode).filter(OtpCode.email == email).delete()

        # Hash the password if provided (will be saved to user after OTP verify)
        pending_pw_hash = None
        if password:
            pending_pw_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

        # Generate and store new OTP
        code = f"{secrets.randbelow(900000) + 100000}"
        otp = OtpCode(
            id=str(uuid.uuid4()),
            email=email,
            code=code,
            purpose=purpose,
            name=otp_name,
            department=otp_dept,
            pending_password=pending_pw_hash,
            attempts=0,
        )
        db.add(otp)
        db.commit()

        # Send email
        send_otp_email(email, code)

        return jsonify({
            "otp_sent": True,
            "purpose": purpose,
            "email": email,
        }), 200

    except Exception as e:
        db.rollback()
        logging.error(f"Login error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/auth/verify-otp")
def verify_otp():
    """Step 2: verify OTP code, create user if needed, return JWT."""
    data = request.get_json()
    email = (data.get("email") or "").strip().lower()
    code = (data.get("code") or "").strip()
    remember_me = data.get("remember_me", False)

    if not email or not code:
        return jsonify({"error": "Email and code are required"}), 400

    db = SessionLocal()
    try:
        otp = (
            db.query(OtpCode)
            .filter(OtpCode.email == email)
            .order_by(OtpCode.created_at.desc())
            .first()
        )

        if not otp:
            return jsonify({"error": "No verification code found. Please request a new one."}), 400

        # Check expiry
        age = datetime.utcnow() - otp.created_at
        if age > timedelta(minutes=OTP_EXPIRY_MINUTES):
            db.delete(otp)
            db.commit()
            return jsonify({"error": "Code expired. Please request a new one."}), 400

        # Check attempt limit
        if otp.attempts >= OTP_MAX_ATTEMPTS:
            db.delete(otp)
            db.commit()
            return jsonify({"error": "Too many attempts. Please request a new code."}), 400

        # Verify code
        if otp.code != code:
            otp.attempts += 1
            db.commit()
            remaining = OTP_MAX_ATTEMPTS - otp.attempts
            return jsonify({
                "error": f"Invalid code. {remaining} attempt(s) remaining."
            }), 400

        # --- OTP is valid ---
        # Save OTP data before deleting
        otp_purpose = otp.purpose
        otp_name = otp.name
        otp_department = otp.department
        otp_pending_password = otp.pending_password
        db.delete(otp)

        # Create or fetch the user
        user = db.query(User).filter(User.email == email).first()

        if not user:
            if otp_purpose == "login":
                # Notion-sourced user
                notion_rows = notion.get_rows_by_email(email)
                if notion_rows:
                    parsed = notion.parse_notion_row(notion_rows[0])
                    role = "admin" if is_admin_email(email) else "traveler"
                    user = User(
                        id=str(uuid.uuid4()),
                        email=email,
                        name=parsed.get("traveler_name") or email.split("@")[0],
                        department=parsed.get("department"),
                        role=role,
                    )
                    db.add(user)
                    db.commit()
                    db.refresh(user)
                    _sync_trips_from_notion(db, email)
                else:
                    # Notion data removed since login — use stored OTP data
                    role = "admin" if is_admin_email(email) else "traveler"
                    user = User(
                        id=str(uuid.uuid4()),
                        email=email,
                        name=otp_name or email.split("@")[0],
                        department=otp_department,
                        role=role,
                    )
                    db.add(user)
                    db.commit()
                    db.refresh(user)

            elif otp_purpose == "register":
                # Self-registration
                role = "admin" if is_admin_email(email) else "traveler"
                user = User(
                    id=str(uuid.uuid4()),
                    email=email,
                    name=otp_name or email.split("@")[0],
                    department=otp_department,
                    role=role,
                )
                db.add(user)
                db.commit()
                db.refresh(user)
        else:
            # Existing user login — update role, sync trips
            user.role = "admin" if is_admin_email(email) else user.role
            try:
                _sync_trips_from_notion(db, email)
            except Exception as sync_err:
                logging.error(f"Trip sync on OTP verify failed: {sync_err}")

        # Save pending password if one was provided during login
        if otp_pending_password:
            user.password_hash = otp_pending_password

        # Save remember_me preference
        user.remembered = bool(remember_me)
        db.commit()

        token = create_token(user.id, user.email, user.role)

        return jsonify({
            "token": token,
            "user": user.to_dict(),
            "needs_password": user.password_hash is None,
        }), 200

    except Exception as e:
        db.rollback()
        logging.error(f"OTP verify error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/auth/set-password")
@require_auth
def set_password():
    """Set or update password for the authenticated user. Max 8 characters."""
    data = request.get_json()
    password = data.get("password") or ""

    if not password or len(password) > 8:
        return jsonify({"error": "Password must be 1-8 characters"}), 400

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == g.user_email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

        hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
        user.password_hash = hashed.decode("utf-8")
        db.commit()

        return jsonify({"message": "Password set successfully"}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Set password error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/auth/forgot-password")
def forgot_password():
    """Send a password-reset OTP to the user's email."""
    data = request.get_json()
    email = (data.get("email") or "").strip().lower()

    if not email:
        return jsonify({"error": "Email is required"}), 400

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()

        if user:
            # Delete existing OTPs for this email
            db.query(OtpCode).filter(OtpCode.email == email).delete()

            # Generate and store OTP
            code = f"{secrets.randbelow(900000) + 100000}"
            otp = OtpCode(
                id=str(uuid.uuid4()),
                email=email,
                code=code,
                purpose="password_reset",
                attempts=0,
            )
            db.add(otp)
            db.commit()

            send_otp_email(email, code)
            logging.info(f"Password reset OTP sent to {email}")

        # Always return success to prevent email enumeration
        return jsonify({"otp_sent": True, "email": email}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Forgot password error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/auth/verify-reset-otp")
def verify_reset_otp():
    """Verify the password-reset OTP and return a scoped reset token."""
    data = request.get_json()
    email = (data.get("email") or "").strip().lower()
    code = (data.get("code") or "").strip()

    if not email or not code:
        return jsonify({"error": "Email and code are required"}), 400

    db = SessionLocal()
    try:
        otp = (
            db.query(OtpCode)
            .filter(OtpCode.email == email)
            .order_by(OtpCode.created_at.desc())
            .first()
        )

        if not otp or otp.purpose != "password_reset":
            return jsonify({"error": "No password reset request found"}), 400

        # Check expiry
        age = datetime.utcnow() - otp.created_at
        if age > timedelta(minutes=OTP_EXPIRY_MINUTES):
            db.delete(otp)
            db.commit()
            return jsonify({"error": "Code expired. Please request a new one."}), 400

        # Check attempts
        if otp.attempts >= OTP_MAX_ATTEMPTS:
            db.delete(otp)
            db.commit()
            return jsonify({"error": "Too many attempts. Please request a new code."}), 400

        # Verify code
        if otp.code != code:
            otp.attempts += 1
            db.commit()
            remaining = OTP_MAX_ATTEMPTS - otp.attempts
            return jsonify({"error": f"Invalid code. {remaining} attempts remaining."}), 400

        # Success — generate a scoped reset token (10 min expiry)
        reset_token = jwt.encode(
            {
                "email": email,
                "purpose": "password_reset",
                "iat": datetime.now(timezone.utc),
                "exp": datetime.now(timezone.utc) + timedelta(minutes=10),
            },
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )

        db.delete(otp)
        db.commit()

        return jsonify({"reset_token": reset_token}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Verify reset OTP error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


import re

_PASSWORD_RE_UPPER = re.compile(r"[A-Z]")
_PASSWORD_RE_LOWER = re.compile(r"[a-z]")
_PASSWORD_RE_DIGIT = re.compile(r"[0-9]")
_PASSWORD_RE_SPECIAL = re.compile(r"[!@#$%^&*()_+\-=\[\]{}|;:',.<>?/]")


@app.post("/auth/reset-password")
def reset_password():
    """Reset password using a scoped reset token."""
    data = request.get_json()
    reset_token = data.get("reset_token") or ""
    password = data.get("password") or ""

    if not reset_token or not password:
        return jsonify({"error": "Reset token and password are required"}), 400

    # Decode reset token
    try:
        payload = jwt.decode(reset_token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        return jsonify({"error": "Reset link has expired. Please start over."}), 401
    except jwt.InvalidTokenError:
        return jsonify({"error": "Invalid reset token."}), 401

    if payload.get("purpose") != "password_reset":
        return jsonify({"error": "Invalid reset token."}), 401

    # Validate password strength
    errors = []
    if len(password) < 8:
        errors.append("at least 8 characters")
    if not _PASSWORD_RE_UPPER.search(password):
        errors.append("1 uppercase letter")
    if not _PASSWORD_RE_LOWER.search(password):
        errors.append("1 lowercase letter")
    if not _PASSWORD_RE_DIGIT.search(password):
        errors.append("1 number")
    if not _PASSWORD_RE_SPECIAL.search(password):
        errors.append("1 special character")
    if errors:
        return jsonify({"error": f"Password must include: {', '.join(errors)}"}), 400

    email = payload["email"]
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

        hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
        user.password_hash = hashed.decode("utf-8")
        db.commit()

        logging.info(f"Password reset successfully for {email}")
        return jsonify({"message": "Password reset successfully"}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Reset password error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/auth/change-password")
@require_auth
def change_password():
    """Change password for an authenticated user (requires current password)."""
    data = request.get_json()
    current_password = data.get("current_password") or ""
    new_password = data.get("new_password") or ""

    if not current_password or not new_password:
        return jsonify({"error": "Current and new password are required"}), 400

    # Validate new password strength
    errors = []
    if len(new_password) < 8:
        errors.append("at least 8 characters")
    if not _PASSWORD_RE_UPPER.search(new_password):
        errors.append("1 uppercase letter")
    if not _PASSWORD_RE_LOWER.search(new_password):
        errors.append("1 lowercase letter")
    if not _PASSWORD_RE_DIGIT.search(new_password):
        errors.append("1 number")
    if not _PASSWORD_RE_SPECIAL.search(new_password):
        errors.append("1 special character")
    if errors:
        return jsonify({"error": f"New password must include: {', '.join(errors)}"}), 400

    email = g.user_email
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

        # Verify current password
        if not user.password_hash or not bcrypt.checkpw(
            current_password.encode("utf-8"), user.password_hash.encode("utf-8")
        ):
            return jsonify({"error": "Current password is incorrect"}), 400

        hashed = bcrypt.hashpw(new_password.encode("utf-8"), bcrypt.gensalt())
        user.password_hash = hashed.decode("utf-8")
        db.commit()

        logging.info(f"Password changed successfully for {email}")
        return jsonify({"message": "Password changed successfully"}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Change password error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.delete("/auth/delete-account")
@require_auth
def delete_account():
    """Delete the authenticated user's account from the database. Notion data is preserved."""
    email = g.user_email
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

        # Collect user's own trip IDs (primary traveler)
        own_trips = db.query(Trip).filter(Trip.traveler_email == email).all()
        own_trip_ids = [t.id for t in own_trips]

        # Delete OTP codes
        db.query(OtpCode).filter(OtpCode.email == email).delete()

        # Delete alerts: user's own + any referencing user's trips
        db.query(Alert).filter(Alert.user_email == email).delete(synchronize_session=False)
        if own_trip_ids:
            db.query(Alert).filter(Alert.trip_id.in_(own_trip_ids)).delete(synchronize_session=False)

        # Delete pending reviews: user's own + any referencing user's trips
        db.query(PendingReview).filter(PendingReview.traveler_email == email).delete(synchronize_session=False)
        if own_trip_ids:
            db.query(PendingReview).filter(PendingReview.trip_id.in_(own_trip_ids)).delete(synchronize_session=False)

        # Delete receipts and their images
        receipts = db.query(Receipt).filter(Receipt.user_id == user.id).all()
        images_to_delete = [r.image_url for r in receipts if r.image_url]
        if user.profile_image:
            images_to_delete.append(user.profile_image)
        delete_files(images_to_delete)
        for receipt in receipts:
            db.delete(receipt)

        # Delete user's own trips (safe now — no FKs point to them)
        if own_trip_ids:
            db.query(Trip).filter(Trip.id.in_(own_trip_ids)).delete(synchronize_session=False)

        # Remove user from co-traveler lists on other people's trips
        co_trips = db.query(Trip).filter(
            Trip.travelers.isnot(None),
            Trip.travelers.contains(email),
        ).all()
        for trip in co_trips:
            emails = [e.strip() for e in trip.travelers.split(",") if e.strip() and e.strip() != email]
            trip.travelers = ", ".join(emails) if emails else None

        # Delete the user
        db.delete(user)
        db.commit()

        logging.info(f"Account deleted for {email}")
        return jsonify({"message": "Account deleted successfully"}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Delete account error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


# =============================================================================
# TRIPS
# =============================================================================

@app.get("/trips")
@require_auth
def get_trips():
    """Get trips. Traveler sees their own, admin sees all.
    Pass ?sync=true to trigger a full Notion sync (used on pull-to-refresh)."""
    db = SessionLocal()
    try:
        # Optional Notion sync (pull-to-refresh)
        if request.args.get("sync") == "true":
            try:
                if g.user_role == "admin":
                    # Admin: sync ALL travelers from Notion
                    parsed_rows = notion.sync_all_trips()
                    for parsed in parsed_rows:
                        email = parsed.get("email", "").strip().lower()
                        if not email:
                            continue
                        user = db.query(User).filter(User.email == email).first()
                        if not user:
                            user = User(
                                id=str(uuid.uuid4()),
                                email=email,
                                name=parsed.get("traveler_name") or email.split("@")[0],
                                department=parsed.get("department"),
                                role="admin" if is_admin_email(email) else "traveler",
                            )
                            db.add(user)
                        # Name priority: App profile > Notion > email prefix
                        if user.name and user.name != email.split("@")[0]:
                            parsed["traveler_name"] = user.name
                        elif not parsed.get("traveler_name"):
                            parsed["traveler_name"] = user.name
                        _upsert_trip(db, parsed, email)
                    db.commit()
                else:
                    _sync_trips_from_notion(db, g.user_email)
            except Exception as sync_err:
                logging.error(f"Pull-to-refresh sync failed: {sync_err}")
                db.rollback()

        if g.user_role == "admin":
            all_trips = (
                db.query(Trip)
                .order_by(Trip.departure_date.desc())
                .limit(200)
                .all()
            )
            trips = [t.to_dict() for t in all_trips]
        else:
            # Trips the traveler owns
            owned = (
                db.query(Trip)
                .filter(Trip.traveler_email == g.user_email)
                .order_by(Trip.departure_date.desc())
                .all()
            )
            # Trips where the traveler is a co-traveler
            co_trips = (
                db.query(Trip)
                .filter(
                    Trip.traveler_email != g.user_email,
                    Trip.travelers.isnot(None),
                    Trip.travelers.contains(g.user_email),
                )
                .order_by(Trip.departure_date.desc())
                .all()
            )
            owned_ids = {t.id for t in owned}
            trips = [t.to_dict() for t in owned]
            for t in co_trips:
                if t.id not in owned_ids:
                    d = t.to_dict()
                    d["is_co_traveler"] = True
                    trips.append(d)
        return jsonify(trips), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.get("/trips/<trip_id>")
@require_auth
def get_trip_detail(trip_id):
    """Get a single trip with its receipts."""
    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        # Travelers can only see their own trips
        if g.user_role != "admin" and trip.traveler_email != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        # Refresh status from Notion if trip has a Notion page
        if trip.notion_page_id:
            try:
                page = notion.get_page(trip.notion_page_id)
                parsed = notion.parse_notion_row(page)
                if parsed.get("status") and parsed["status"] != trip.status:
                    trip.status = parsed["status"]
                    db.commit()
                    logging.info(f"Trip {trip_id} status updated to '{trip.status}' from Notion")
            except Exception as sync_err:
                logging.error(f"Notion status refresh failed for trip {trip_id}: {sync_err}")

        receipts = (
            db.query(Receipt)
            .filter(Receipt.trip_id == trip_id)
            .order_by(Receipt.created_at.desc())
            .all()
        )

        result = trip.to_dict()
        result["receipts"] = [r.to_dict() for r in receipts]
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/trips/sync")
@require_auth
@require_admin
def sync_trips():
    """Admin: trigger full Notion → PostgreSQL sync."""
    db = SessionLocal()
    try:
        parsed_rows = notion.sync_all_trips()
        synced = 0

        for parsed in parsed_rows:
            email = parsed.get("email", "").strip().lower()
            if not email:
                continue

            # Ensure user exists
            user = db.query(User).filter(User.email == email).first()
            if not user:
                user = User(
                    id=str(uuid.uuid4()),
                    email=email,
                    name=parsed.get("traveler_name") or email.split("@")[0],
                    department=parsed.get("department"),
                    role="admin" if is_admin_email(email) else "traveler",
                )
                db.add(user)

            if not parsed.get("traveler_name"):
                parsed["traveler_name"] = user.name
            _upsert_trip(db, parsed, email)
            synced += 1

        db.commit()

        # Create admin placeholders for any category gaps after sync
        for parsed in parsed_rows:
            email = parsed.get("email", "").strip().lower()
            notion_page_id = parsed.get("notion_page_id")
            if not email or not notion_page_id:
                continue
            trip = db.query(Trip).filter(Trip.notion_page_id == notion_page_id).first()
            if trip:
                _create_admin_placeholders(db, trip)
        db.commit()

        return jsonify({"status": "synced", "count": synced}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Sync error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/trips")
@require_auth
def create_trip():
    """Create a new trip from the app. Creates in both PostgreSQL and Notion."""
    data = request.get_json()

    trip_purpose = (data.get("trip_purpose") or "").strip()
    destination = (data.get("destination") or "").strip()
    departure_date_str = data.get("departure_date")
    return_date_str = data.get("return_date")

    if not trip_purpose and not destination:
        return jsonify({"error": "Trip purpose or destination is required"}), 400

    # Parse dates if provided
    departure_date = None
    return_date = None
    if departure_date_str:
        try:
            date_str = departure_date_str.split("T")[0] if "T" in departure_date_str else departure_date_str
            departure_date = datetime.strptime(date_str, "%Y-%m-%d").date()
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid departure_date format"}), 400
    if return_date_str:
        try:
            date_str = return_date_str.split("T")[0] if "T" in return_date_str else return_date_str
            return_date = datetime.strptime(date_str, "%Y-%m-%d").date()
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid return_date format"}), 400

    db = SessionLocal()
    try:
        # If admin specifies a traveler, assign trip to that traveler
        target_email = g.user_email
        if g.user_role == "admin" and data.get("traveler_email"):
            target_email = data["traveler_email"].strip().lower()

        user = db.query(User).filter(User.email == target_email).first()
        if not user:
            return jsonify({"error": "Traveler not found"}), 404

        # Create in Notion first to get the page ID
        notion_page_id = None
        try:
            notion_result = notion.create_trip_page(
                traveler_name=user.name,
                email=user.email,
                department=user.department,
                trip_purpose=trip_purpose,
                destination=destination,
                departure_date=departure_date,
                return_date=return_date,
            )
            notion_page_id = notion_result.get("id")
            logging.info(f"Notion page created: {notion_page_id}")
        except Exception as notion_err:
            logging.error(f"Notion page creation failed: {notion_err}")
            # Continue — trip will be created locally without Notion link

        # Fetch destination cover image
        cover_image_url = None
        if destination:
            try:
                cover_image_url = fetch_destination_image(destination)
            except Exception as img_err:
                logging.error(f"Unsplash fetch failed for '{destination}': {img_err}")

        # Parse optional fields
        budget = 0.0
        try:
            budget = float(data.get("budget", 0)) if data.get("budget") else 0.0
        except (ValueError, TypeError):
            pass
        status = (data.get("status") or "").strip() or "Not Started"
        travel_type = (data.get("travel_type") or "").strip() or None
        category = (data.get("category") or "").strip() or None
        description = (data.get("description") or "").strip() or None
        travelers = (data.get("travelers") or "").strip() or None

        # Create in PostgreSQL
        trip = Trip(
            id=str(uuid.uuid4()),
            notion_page_id=notion_page_id,
            traveler_email=target_email,
            traveler_name=user.name,
            department=data.get("department") or user.department,
            trip_purpose=trip_purpose or None,
            destination=destination or None,
            departure_date=departure_date,
            return_date=return_date,
            status=status,
            cover_image_url=cover_image_url,
            budget=budget,
            travel_type=travel_type,
            category=category,
            description=description,
            travelers=travelers,
            synced_at=datetime.now(timezone.utc) if notion_page_id else None,
        )
        db.add(trip)

        # Notify admins (only if created by traveler, not by admin themselves)
        dest = destination or trip_purpose or "a trip"
        if g.user_role != "admin":
            _notify_admins(
                db, target_email,
                title=f"{user.name} created a new trip — {dest}",
                message=f"{user.name} created a new trip to {dest}.",
                trip_id=trip.id,
            )
            _create_pending_review(
                db, target_email, user.name,
                title=f"{user.name} created a new trip — {dest}",
                review_type="trip", action="created",
                trip_id=trip.id,
            )
        else:
            # Admin created a trip for a traveler — notify the traveler
            first_name = (user.name or "").split(" ")[0] or "there"
            _notify_traveler(
                db, target_email,
                title=f"Admin created a new trip for you — {dest}",
                message=f"Hi {first_name}, the admin has created a new trip to {dest} for you.",
                trip_id=trip.id,
            )

        db.commit()
        db.refresh(trip)

        return jsonify(trip.to_dict()), 201
    except Exception as e:
        db.rollback()
        logging.error(f"Create trip error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


def _upsert_trip(db, parsed, traveler_email):
    """Insert or update a Trip record from parsed Notion data."""
    notion_page_id = parsed["notion_page_id"]
    existing = db.query(Trip).filter(Trip.notion_page_id == notion_page_id).first()

    # Fetch cover image if destination changed or missing
    destination = parsed.get("destination")

    if existing:
        old_destination = existing.destination
        # Name priority: App profile name > Notion name > existing
        # If traveler has an app account, use their profile name
        traveler_user = db.query(User).filter(
            User.email == existing.traveler_email
        ).first()
        if traveler_user and traveler_user.name:
            existing.traveler_name = traveler_user.name
        elif parsed.get("traveler_name"):
            existing.traveler_name = parsed["traveler_name"]
        # Department always from Notion (org's system of record)
        if parsed.get("department"):
            existing.department = parsed["department"]
        existing.accommodation_cost = parsed.get("accommodation_cost", 0.0)
        existing.flight_cost = parsed.get("flight_cost", 0.0)
        existing.ground_transportation = parsed.get("ground_transportation", 0.0)
        existing.registration_cost = parsed.get("registration_cost", 0.0)
        existing.meals = parsed.get("meals", 0.0)
        existing.other_as_cost = parsed.get("other_as_cost", 0.0)
        existing.total_expenses = parsed.get("total_expenses", 0.0)
        existing.advance = parsed.get("advance", 0.0)
        existing.claim = parsed.get("claim", 0.0)
        existing.synced_at = datetime.now(timezone.utc)
        # Only fill these from Notion if local value is empty
        # — protects edits made via the app
        if parsed.get("trip_purpose") and not existing.trip_purpose:
            existing.trip_purpose = parsed["trip_purpose"]
        if parsed.get("destination") and not existing.destination:
            existing.destination = parsed["destination"]
        if parsed.get("departure_date") and not existing.departure_date:
            existing.departure_date = parsed["departure_date"]
        if parsed.get("return_date") and not existing.return_date:
            existing.return_date = parsed["return_date"]
        if parsed.get("status"):
            existing.status = parsed["status"]
        # Preserve app-only fields (budget, category, description, travelers)
        # Fetch image only if no image yet (don't overwrite app-edited cover)
        if existing.destination and not existing.cover_image_url:
            try:
                img_url = fetch_destination_image(existing.destination)
                if img_url:
                    existing.cover_image_url = img_url
            except Exception:
                pass
    else:
        cover_image_url = fetch_destination_image(destination) if destination else None
        trip = Trip(
            id=str(uuid.uuid4()),
            notion_page_id=notion_page_id,
            traveler_email=traveler_email,
            traveler_name=parsed.get("traveler_name", ""),
            department=parsed.get("department"),
            trip_purpose=parsed.get("trip_purpose"),
            destination=destination,
            departure_date=parsed.get("departure_date"),
            return_date=parsed.get("return_date"),
            status=parsed.get("status"),
            accommodation_cost=parsed.get("accommodation_cost", 0.0),
            flight_cost=parsed.get("flight_cost", 0.0),
            ground_transportation=parsed.get("ground_transportation", 0.0),
            registration_cost=parsed.get("registration_cost", 0.0),
            meals=parsed.get("meals", 0.0),
            other_as_cost=parsed.get("other_as_cost", 0.0),
            total_expenses=parsed.get("total_expenses", 0.0),
            advance=parsed.get("advance", 0.0),
            claim=parsed.get("claim", 0.0),
            cover_image_url=cover_image_url,
            synced_at=datetime.now(timezone.utc),
        )
        db.add(trip)


def _create_admin_placeholders(db, trip):
    """Create placeholder receipts for admin-added costs that have no matching receipt.

    Only creates a placeholder when a trip category has a non-zero Notion amount
    but ZERO traveler-scanned receipts in that category. This avoids false
    positives from rounding differences or double-push issues.
    """
    CATEGORY_MAP = {
        "Accommodation Cost": "accommodation_cost",
        "Flight Cost": "flight_cost",
        "Ground Transportation": "ground_transportation",
        "Registration Cost": "registration_cost",
        "Meals": "meals",
        "Other AS Cost": "other_as_cost",
    }

    # Get existing receipts for this trip
    existing_receipts = (
        db.query(Receipt)
        .filter(Receipt.trip_id == trip.id)
        .all()
    )

    # Count receipts that are "accounted for" per category:
    # - traveler-scanned receipts (added_by != "admin")
    # - admin receipts where traveler already attached an image (image_url is set)
    accounted_totals = {}
    for cat in CATEGORY_MAP:
        accounted = [
            r for r in existing_receipts
            if r.travel_category == cat
            and (r.added_by != "admin" or r.image_url is not None)
        ]
        accounted_totals[cat] = sum((r.total or 0) for r in accounted)

    for category, field_name in CATEGORY_MAP.items():
        notion_amount = getattr(trip, field_name, 0) or 0
        traveler_amount = accounted_totals.get(category, 0)

        # Only create placeholder if Notion has a cost AND the traveler's
        # scanned receipts don't fully account for it
        gap = round(notion_amount - traveler_amount, 2)

        # Check if a placeholder already exists for this category
        existing_placeholder = next(
            (r for r in existing_receipts
             if r.travel_category == category
             and r.added_by == "admin"
             and r.image_url is None),
            None
        )

        if gap > 0.01:
            if existing_placeholder:
                # Update the existing placeholder amount
                existing_placeholder.total = gap
            else:
                # Only create if there are NO accounted-for receipts in this category
                has_accounted_receipts = any(
                    r for r in existing_receipts
                    if r.travel_category == category
                    and (r.added_by != "admin" or r.image_url is not None)
                )
                if not has_accounted_receipts:
                    placeholder = Receipt(
                        id=str(uuid.uuid4()),
                        user_id=trip.traveler_email,
                        trip_id=trip.id,
                        travel_category=category,
                        merchant=f"{category} (Admin)",
                        total=gap,
                        added_by="admin",
                        image_url=None,
                        items=None,
                        ocr_raw=None,
                    )
                    db.add(placeholder)
                    logging.info(
                        f"Created admin placeholder for trip {trip.id}: "
                        f"{category} = {gap}"
                    )
        elif existing_placeholder:
            # Gap is zero or negative — remove stale placeholder
            db.delete(existing_placeholder)
            logging.info(
                f"Removed stale admin placeholder for trip {trip.id}: {category}"
            )


def _sync_trips_from_notion(db, email):
    """Full bidirectional sync: upsert Notion trips and remove deleted ones."""
    notion_rows = notion.get_rows_by_email(email)

    # Upsert all trips found in Notion
    user = db.query(User).filter(User.email == email).first()
    notion_page_ids = set()
    for row in notion_rows:
        parsed_trip = notion.parse_notion_row(row)
        # Name priority: App profile > Notion > existing
        if user and user.name and user.name != email.split("@")[0]:
            parsed_trip["traveler_name"] = user.name
        elif not parsed_trip.get("traveler_name") and user:
            parsed_trip["traveler_name"] = user.name
        _upsert_trip(db, parsed_trip, email)
        notion_page_ids.add(parsed_trip["notion_page_id"])

    # Delete PostgreSQL trips whose Notion page no longer exists
    local_notion_trips = (
        db.query(Trip)
        .filter(Trip.traveler_email == email, Trip.notion_page_id.isnot(None))
        .all()
    )
    for trip in local_notion_trips:
        if trip.notion_page_id not in notion_page_ids:
            # Also delete associated alerts and receipts
            db.query(Alert).filter(Alert.trip_id == trip.id).delete()
            receipts = db.query(Receipt).filter(Receipt.trip_id == trip.id).all()
            delete_files([r.image_url for r in receipts if r.image_url])
            for r in receipts:
                db.delete(r)
            db.delete(trip)
            logging.info(f"Removed trip {trip.id} (Notion page {trip.notion_page_id} no longer exists)")

    db.commit()

    # Create admin placeholders for category gaps
    for row in notion_rows:
        parsed_trip = notion.parse_notion_row(row)
        notion_page_id = parsed_trip.get("notion_page_id")
        if notion_page_id:
            trip = db.query(Trip).filter(Trip.notion_page_id == notion_page_id).first()
            if trip:
                _create_admin_placeholders(db, trip)
    db.commit()

    logging.info(f"Synced {len(notion_rows)} trips from Notion for {email}")


# =============================================================================
# RECEIPT SCANNING (modified for travel categories)
# =============================================================================

@app.post("/expense")
@require_auth
def expense():
    """Scan a receipt: OCR + Gemini categorization into travel categories."""
    file = request.files.get("file")
    if not file:
        return jsonify({"error": "No file provided"}), 400

    trip_id = request.form.get("trip_id")
    payment_method = request.form.get("payment_method", "personal")
    if payment_method not in ("personal", "corporate"):
        payment_method = "personal"

    img = file.read()

    # Compress image if larger than 4 MB (Azure limit)
    if len(img) > 4 * 1024 * 1024:
        from PIL import Image as PILImage
        import io
        pil_img = PILImage.open(io.BytesIO(img))
        # Convert RGBA/palette to RGB for JPEG
        if pil_img.mode in ("RGBA", "P"):
            pil_img = pil_img.convert("RGB")
        # Resize if very large
        max_dim = 2048
        if max(pil_img.size) > max_dim:
            pil_img.thumbnail((max_dim, max_dim), PILImage.LANCZOS)
        buf = io.BytesIO()
        pil_img.save(buf, format="JPEG", quality=80)
        img = buf.getvalue()
        logging.info(f"Compressed image to {len(img)} bytes")

    try:
        # Step 1: Azure OCR
        data = analyze_receipt_azure(img)

        # Step 2: Gemini — currency + travel category + merchant fallback
        merchant = data.get("merchant") or None
        merchant_confidence = (data.get("confidences") or {}).get("merchant", 0)
        address = data.get("address", "")
        raw_lines = data.get("raw_lines", [])
        items = [item.get("name", "") for item in data.get("items", []) if item.get("name")]
        total_amount = data.get("total")
        needs_merchant = not merchant or merchant_confidence < 0.5

        prompt = f"""
Analyze this receipt and return JSON with the following fields:

1. **MERCHANT_NAME**: The name of the store, restaurant, or business on this receipt.
   - Read the OCR text carefully — the merchant name is usually at the top of the receipt (first few lines), often in large/bold text.
   - Look for business names, franchise names, or brand names.
   - Do NOT use addresses, phone numbers, or slogans as the merchant name.
   - If you truly cannot determine it, return "Unknown".
   {"- The OCR system detected: " + repr(merchant) + " (low confidence) — verify or correct this." if merchant and needs_merchant else ""}

2. **CURRENCY**: Detect which currency symbol is used
   - Look in the OCR text for symbols: $, ₹, €, £
   - Look for currency codes: USD, INR, EUR, GBP, Rs, Rs.
   - Check the address/location for clues
   - Return ONLY one of these symbols: $, ₹, €, £

3. **TRAVEL_CATEGORY**: Classify into exactly ONE travel expense category
   - Choose from: {', '.join(TRAVEL_CATEGORIES)}
   - Based on merchant name, items, and receipt context

Receipt Information:
- OCR Merchant: {merchant or "Not detected"}
- Address: {address}
- Total: {total_amount}
- Items: {items}
- OCR Text (first 20 lines):
{chr(10).join(raw_lines[:20])}

Currency Detection Rules:
- If you see $ or USD → return "$"
- If you see ₹ or INR or Rs or Rs. or GSTIN → return "₹"
- If you see € or EUR or VAT (Europe) → return "€"
- If you see £ or GBP → return "£"
- If address indicates India → return "₹"
- If address indicates UK → return "£"
- If address indicates Europe → return "€"
- Default to "$" if unclear

Travel Category Rules (apply in this order — first match wins):
- Restaurants, meals, food, dining, cafeteria, coffee shops, fast food, catering, per diem meals, breakfast, lunch, dinner, snacks, DoorDash, Uber Eats, Grubhub → "Meals"
- Gas stations (Chevron, Shell, BP, 76, Exxon, Mobil, Costco fuel, etc.), parking, tolls, metro/subway fares, office supplies, miscellaneous → "Other AS Cost"
- Hotels, Airbnb, motels, lodging, room charges, hostel → "Accommodation Cost"
- Airlines, flights, boarding passes, air tickets → "Flight Cost"
- Uber, Lyft, taxi, rental car, car rental agencies (Hertz, Enterprise, Avis) → "Ground Transportation"
- Conference registration, event tickets, seminar fees, admission → "Registration Cost"
- Anything else not listed above → "Other AS Cost"

IMPORTANT: Gas stations and fuel purchases are NEVER "Ground Transportation". They are always "Other AS Cost".

Return ONLY valid JSON in this EXACT format (no markdown, no extra text):
{{
  "merchant_name": "Starbucks",
  "currency": "$",
  "travel_category": "Meals"
}}
"""

        model = genai.GenerativeModel("gemini-2.0-flash")
        try:
            response = gemini_call_with_retry(model, prompt)
        except google.api_core.exceptions.ResourceExhausted:
            return jsonify({"error": "AI service is busy. Please try again in a moment."}), 429
        except google.api_core.exceptions.ServiceUnavailable:
            return jsonify({"error": "AI service unavailable"}), 503
        except Exception as gemini_err:
            logging.error(f"GEMINI ERROR: {gemini_err}")
            raise

        text = response.text.strip()

        # Parse JSON (handle markdown code blocks)
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        gemini_result = json.loads(text)

        # Validate currency
        detected_currency = gemini_result.get("currency", "$")
        if detected_currency not in ["$", "₹", "€", "£"]:
            detected_currency = "$"

        # Validate travel category
        detected_category = gemini_result.get("travel_category", "Other AS Cost")
        if detected_category not in TRAVEL_CATEGORIES:
            detected_category = "Other AS Cost"

        # Merchant fallback: use Gemini's answer when Azure missed or had low confidence
        gemini_merchant = (gemini_result.get("merchant_name") or "").strip()
        if needs_merchant and gemini_merchant and gemini_merchant.lower() != "unknown":
            data["merchant"] = gemini_merchant
            logging.info(f"Merchant fallback: Azure={merchant!r} → Gemini={gemini_merchant!r}")

        data["currency"] = detected_currency
        data["travel_category"] = detected_category
        data["category"] = detected_category  # backward compat

        # Save receipt image to Supabase Storage
        receipt_id = str(uuid.uuid4())
        image_filename = f"{receipt_id}.jpg"
        upload_file(image_filename, img, content_type="image/jpeg")

        # Save to PostgreSQL
        db = SessionLocal()
        try:
            receipt = Receipt(
                id=receipt_id,
                user_id=g.user_email,
                trip_id=trip_id,
                travel_category=detected_category,
                image_url=image_filename,
                merchant=data.get("merchant"),
                address=data.get("address"),
                total=data.get("total"),
                currency=detected_currency,
                category=detected_category,
                receipt_date=data.get("date") or datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                items=data.get("items"),
                ocr_raw=data,
                payment_method=payment_method,
            )
            db.add(receipt)

            # Auto-confirm: update trip totals and push to Notion
            if trip_id and detected_category:
                trip = db.query(Trip).filter(Trip.id == trip_id).first()
                if trip:
                    amount = data.get("total") or 0.0
                    _add_to_trip_category(trip, detected_category, amount)

                    # Push to Notion if trip has a Notion page
                    if trip.notion_page_id:
                        try:
                            notion.add_to_expense_column(
                                trip.notion_page_id,
                                detected_category,
                                amount,
                            )
                            logging.info(f"Notion auto-updated: {detected_category} += {amount} for trip {trip.id}")
                        except Exception as notion_err:
                            logging.error(f"Notion auto-write failed (receipt saved locally): {notion_err}")
                            receipt.notion_sync_pending = True
                            data["warning"] = "Receipt saved but Notion sync delayed. It will sync automatically shortly."

            # Notify about the new receipt
            merchant_name = data.get("merchant") or "Unknown"
            amount_str = f"{detected_currency}{data.get('total', '?')}"
            trip_dest = ""
            _trip = None
            if trip_id:
                _trip = db.query(Trip).filter(Trip.id == trip_id).first()
                if _trip:
                    trip_dest = _trip.destination or _trip.trip_purpose or ""

            if g.user_role != "admin":
                user = db.query(User).filter(User.email == g.user_email).first()
                traveler_name = user.name if user else g.user_email
                _notify_admins(
                    db, g.user_email,
                    title=f"{traveler_name} added a {amount_str} receipt from {merchant_name}",
                    message=f"{traveler_name} uploaded a {amount_str} receipt from {merchant_name} ({detected_category}){f' for {trip_dest}' if trip_dest else ''}.",
                    trip_id=trip_id,
                )
                _create_pending_review(
                    db, g.user_email, traveler_name,
                    title=f"{traveler_name} added a {amount_str} receipt from {merchant_name}",
                    review_type="receipt", action="uploaded",
                    trip_id=trip_id, receipt_id=receipt_id,
                    details=f"{amount_str} · {detected_category}{f' · {trip_dest}' if trip_dest else ''}",
                )
            elif _trip and _trip.traveler_email:
                # Admin added a receipt to a traveler's trip — notify the traveler
                traveler = db.query(User).filter(User.email == _trip.traveler_email).first()
                first_name = ((traveler.name or "").split(" ")[0] if traveler else "") or "there"
                _notify_traveler(
                    db, _trip.traveler_email,
                    title=f"Admin added a {amount_str} receipt from {merchant_name}",
                    message=f"Hi {first_name}, the admin added a {amount_str} receipt from {merchant_name} ({detected_category}) to your trip {trip_dest}.",
                    trip_id=trip_id,
                )

            db.commit()
            data["receipt_id"] = receipt.id
            data["receipt"] = receipt.to_dict()
            # Include updated trip so frontend can refresh instantly
            if trip_id:
                trip = db.query(Trip).filter(Trip.id == trip_id).first()
                if trip:
                    data["trip"] = trip.to_dict()
        except Exception as db_err:
            db.rollback()
            logging.error(f"DB save error: {db_err}")
        finally:
            db.close()

        return jsonify(data), 200

    except Exception as e:
        logging.error(f"Expense error: {e}")
        return jsonify({"error": str(e)}), 500


# =============================================================================
# RECEIPT CONFIRM (traveler confirms category → writes to Notion)
# =============================================================================

@app.post("/receipts/<receipt_id>/confirm")
@require_auth
def confirm_receipt(receipt_id):
    """Traveler confirms or overrides the travel category. Pushes to Notion."""
    data = request.get_json()
    travel_category = data.get("travel_category")

    if travel_category not in TRAVEL_CATEGORIES:
        return jsonify({"error": f"Invalid category. Must be one of: {TRAVEL_CATEGORIES}"}), 400

    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        # Only owner or admin can confirm
        if g.user_role != "admin" and receipt.user_id != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        # Update category
        receipt.travel_category = travel_category
        receipt.category = travel_category

        # If linked to a trip, update trip totals and push to Notion
        if receipt.trip_id:
            trip = db.query(Trip).filter(Trip.id == receipt.trip_id).first()
            if trip:
                # Add to the correct expense column in PostgreSQL
                amount = receipt.total or 0.0
                _add_to_trip_category(trip, travel_category, amount)

                # Push to Notion
                try:
                    notion.add_to_expense_column(
                        trip.notion_page_id,
                        travel_category,
                        amount,
                    )
                    logging.info(f"Notion updated: {travel_category} += {amount} for trip {trip.id}")
                except Exception as notion_err:
                    logging.error(f"Notion write failed (receipt saved locally): {notion_err}")

        # Notify admins
        if g.user_role != "admin":
            user = db.query(User).filter(User.email == g.user_email).first()
            traveler_name = user.name if user else g.user_email
            merchant = receipt.merchant or "a receipt"
            _notify_admins(
                db, g.user_email,
                title=f"{traveler_name} changed category to {travel_category} for {merchant}",
                message=f"{traveler_name} changed category to {travel_category} for {merchant}.",
                trip_id=receipt.trip_id,
            )
            _create_pending_review(
                db, g.user_email, traveler_name,
                title=f"{traveler_name} changed category to {travel_category} for {merchant}",
                review_type="receipt", action="updated",
                trip_id=receipt.trip_id, receipt_id=receipt.id,
            )

        db.commit()
        return jsonify({"status": "confirmed", "receipt": receipt.to_dict()}), 200

    except Exception as e:
        db.rollback()
        logging.error(f"Confirm error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/receipts/<receipt_id>/attach")
@require_auth
def attach_receipt_image(receipt_id):
    """Attach a scanned receipt image to an admin-created placeholder."""
    file = request.files.get("file")
    if not file:
        return jsonify({"error": "No file provided"}), 400

    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        # Only owner or admin can attach
        if g.user_role != "admin" and receipt.user_id != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        if receipt.added_by != "admin":
            return jsonify({"error": "Can only attach to admin-created placeholders"}), 400

        img = file.read()

        # Compress image if larger than 4 MB
        if len(img) > 4 * 1024 * 1024:
            from PIL import Image as PILImage
            import io
            pil_img = PILImage.open(io.BytesIO(img))
            if pil_img.mode in ("RGBA", "P"):
                pil_img = pil_img.convert("RGB")
            max_dim = 2048
            if max(pil_img.size) > max_dim:
                pil_img.thumbnail((max_dim, max_dim), PILImage.LANCZOS)
            buf = io.BytesIO()
            pil_img.save(buf, format="JPEG", quality=80)
            img = buf.getvalue()

        # Save image file to Supabase Storage
        filename = f"{uuid.uuid4()}.jpg"
        upload_file(filename, img, content_type="image/jpeg")

        # Update the placeholder receipt with the image
        receipt.image_url = filename

        # Notify admins
        if g.user_role != "admin":
            user = db.query(User).filter(User.email == g.user_email).first()
            traveler_name = user.name if user else g.user_email
            merchant = receipt.merchant or "a receipt"
            _notify_admins(
                db, g.user_email,
                title=f"{traveler_name} attached an image to {merchant}",
                message=f"{traveler_name} attached an image to {merchant}.",
                trip_id=receipt.trip_id,
            )
            _create_pending_review(
                db, g.user_email, traveler_name,
                title=f"{traveler_name} attached an image to {merchant}",
                review_type="receipt", action="updated",
                trip_id=receipt.trip_id, receipt_id=receipt.id,
            )

        db.commit()

        # Return updated receipt and trip
        result = {"receipt": receipt.to_dict()}
        if receipt.trip_id:
            trip = db.query(Trip).filter(Trip.id == receipt.trip_id).first()
            if trip:
                result["trip"] = trip.to_dict()

        return jsonify(result), 200

    except Exception as e:
        db.rollback()
        logging.error(f"Attach receipt error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


def _add_to_trip_category(trip, category, amount):
    """Add amount to the correct expense column on a Trip object."""
    if category == "Accommodation Cost":
        trip.accommodation_cost = (trip.accommodation_cost or 0) + amount
    elif category == "Flight Cost":
        trip.flight_cost = (trip.flight_cost or 0) + amount
    elif category == "Ground Transportation":
        trip.ground_transportation = (trip.ground_transportation or 0) + amount
    elif category == "Registration Cost":
        trip.registration_cost = (trip.registration_cost or 0) + amount
    elif category == "Meals":
        trip.meals = (trip.meals or 0) + amount
    elif category == "Other AS Cost":
        trip.other_as_cost = (trip.other_as_cost or 0) + amount
    trip.total_expenses = (
        (trip.accommodation_cost or 0)
        + (trip.flight_cost or 0)
        + (trip.ground_transportation or 0)
        + (trip.registration_cost or 0)
        + (trip.meals or 0)
        + (trip.other_as_cost or 0)
    )


# =============================================================================
@app.get("/receipts/<receipt_id>")
@require_auth
def get_receipt(receipt_id):
    """Get a single receipt by ID."""
    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404
        if g.user_role != "admin" and receipt.user_id != g.user_email:
            return jsonify({"error": "Access denied"}), 403
        return jsonify(receipt.to_dict()), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


# RECEIPT IMAGE
# =============================================================================

@app.get("/receipts/<receipt_id>/image")
@require_auth
def get_receipt_image(receipt_id):
    """Serve receipt image. Accessible to receipt owner and admins."""
    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        if g.user_role != "admin" and receipt.user_id != g.user_email:
            # Allow co-travelers of the same trip to view the image
            allowed = False
            if receipt.trip_id:
                trip = db.query(Trip).filter(Trip.id == receipt.trip_id).first()
                if trip:
                    if trip.traveler_email == g.user_email:
                        allowed = True
                    elif trip.travelers and g.user_email in [
                        e.strip() for e in trip.travelers.split(",")
                    ]:
                        allowed = True
            if not allowed:
                return jsonify({"error": "Access denied"}), 403

        if not receipt.image_url:
            return jsonify({"error": "No image available"}), 404

        try:
            data = download_file(receipt.image_url)
            return Response(data, mimetype="image/jpeg")
        except Exception:
            return jsonify({"error": "Image file not found"}), 404
    finally:
        db.close()


# =============================================================================
# PROFILE IMAGE
# =============================================================================

@app.post("/profile/image")
@require_auth
def upload_profile_image():
    """Upload or replace the user's profile picture."""
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    file = request.files["file"]
    if not file.filename:
        return jsonify({"error": "Empty filename"}), 400

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == g.user_email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

        # Delete old profile image if exists
        if user.profile_image:
            delete_file(user.profile_image)

        # Save new image to Supabase Storage
        ext = os.path.splitext(file.filename)[1] or ".jpg"
        filename = f"profile_{user.id}{ext}"
        content_type = file.content_type or "image/jpeg"
        upload_file(filename, file.read(), content_type=content_type)

        user.profile_image = filename
        db.commit()

        return jsonify({"profile_image": filename}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Profile image upload error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.delete("/profile/image")
@require_auth
def delete_profile_image():
    """Remove the user's profile picture."""
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == g.user_email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

        if user.profile_image:
            delete_file(user.profile_image)
            user.profile_image = None
            db.commit()

        return jsonify({"message": "Profile image removed"}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Profile image delete error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.get("/profile/image")
@require_auth
def get_profile_image():
    """Serve the user's profile picture."""
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == g.user_email).first()
        if not user or not user.profile_image:
            return jsonify({"error": "No profile image"}), 404

        try:
            data = download_file(user.profile_image)
            return Response(data, mimetype="image/jpeg")
        except Exception:
            return jsonify({"error": "Image file not found"}), 404
    finally:
        db.close()


@app.get("/admin/traveler/<path:email>/image")
@require_auth
def get_traveler_image(email):
    """Admin: serve a specific traveler's profile image."""
    if g.user_role != "admin":
        return jsonify({"error": "Admin only"}), 403
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email.lower().strip()).first()
        if not user or not user.profile_image:
            return jsonify({"error": "No profile image"}), 404
        try:
            data = download_file(user.profile_image)
            return Response(data, mimetype="image/jpeg")
        except Exception:
            return jsonify({"error": "Image file not found"}), 404
    finally:
        db.close()


# =============================================================================
# RECEIPTS LIST (legacy + updated)
# =============================================================================

@app.get("/receipts")
@require_auth
def get_receipts():
    """Get receipts. Traveler sees their own, admin can see all."""
    user_filter = request.args.get("user_id")
    trip_filter = request.args.get("trip_id")

    db = SessionLocal()
    try:
        query = db.query(Receipt)

        if g.user_role == "admin" and user_filter:
            query = query.filter(Receipt.user_id == user_filter)
        elif g.user_role != "admin":
            if trip_filter:
                # For a specific trip, check if the user is owner or co-traveler
                trip = db.query(Trip).filter(Trip.id == trip_filter).first()
                is_member = False
                if trip:
                    if trip.traveler_email == g.user_email:
                        is_member = True
                    elif trip.travelers and g.user_email in [
                        e.strip() for e in trip.travelers.split(",")
                    ]:
                        is_member = True
                if is_member:
                    # Show ALL receipts for this trip (from all members)
                    query = query.filter(Receipt.trip_id == trip_filter)
                else:
                    # Not a member — only their own receipts for this trip
                    query = query.filter(
                        Receipt.user_id == g.user_email,
                        Receipt.trip_id == trip_filter,
                    )
            else:
                # General receipts: own receipts + receipts from co-traveler trips
                co_trips = db.query(Trip).filter(
                    Trip.traveler_email != g.user_email,
                    Trip.travelers.isnot(None),
                    Trip.travelers.contains(g.user_email),
                ).all()
                co_trip_ids = [t.id for t in co_trips]
                logging.info(
                    f"[RECEIPTS] user={g.user_email}, co_trips found={len(co_trips)}, "
                    f"co_trip_ids={co_trip_ids}"
                )
                if co_trip_ids:
                    query = query.filter(
                        db_or(
                            Receipt.user_id == g.user_email,
                            Receipt.trip_id.in_(co_trip_ids),
                        )
                    )
                else:
                    query = query.filter(Receipt.user_id == g.user_email)
        else:
            if trip_filter:
                query = query.filter(Receipt.trip_id == trip_filter)

        receipts = query.order_by(Receipt.created_at.desc()).all()
        for r in receipts:
            if r.added_by == "admin":
                logging.info(f"ADMIN RECEIPT: id={r.id}, added_by={r.added_by}, image_url={r.image_url}, merchant={r.merchant}, total={r.total}")
        return jsonify([r.to_dict() for r in receipts]), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.put("/trips/<trip_id>")
@require_auth
def update_trip(trip_id):
    """Update a trip's editable fields."""
    data = request.get_json()
    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        is_co_traveler = trip.travelers and g.user_email in [e.strip() for e in trip.travelers.split(",")]
        if g.user_role != "admin" and trip.traveler_email != g.user_email and not is_co_traveler:
            return jsonify({"error": "Access denied"}), 403

        # Snapshot old values for change tracking
        old_vals = {
            "trip_purpose": trip.trip_purpose,
            "destination": trip.destination,
            "departure_date": str(trip.departure_date) if trip.departure_date else None,
            "return_date": str(trip.return_date) if trip.return_date else None,
            "budget": trip.budget,
            "description": trip.description,
            "travelers": trip.travelers,
        }

        # Updatable fields
        if "trip_purpose" in data:
            trip.trip_purpose = (data["trip_purpose"] or "").strip() or None
        if "destination" in data:
            new_dest = (data["destination"] or "").strip() or None
            # If destination changed, fetch a new cover image
            if new_dest != trip.destination and new_dest:
                try:
                    trip.cover_image_url = fetch_destination_image(new_dest) or trip.cover_image_url
                except Exception as img_err:
                    logging.error(f"Unsplash fetch failed for '{new_dest}': {img_err}")
            trip.destination = new_dest
        if "departure_date" in data:
            try:
                raw = data["departure_date"]
                if raw:
                    date_str = raw.split("T")[0] if "T" in raw else raw
                    trip.departure_date = datetime.strptime(date_str, "%Y-%m-%d").date()
                else:
                    trip.departure_date = None
            except (ValueError, TypeError) as e:
                logging.error(f"departure_date parse error: {e}")
        if "return_date" in data:
            try:
                raw = data["return_date"]
                if raw:
                    date_str = raw.split("T")[0] if "T" in raw else raw
                    trip.return_date = datetime.strptime(date_str, "%Y-%m-%d").date()
                else:
                    trip.return_date = None
            except (ValueError, TypeError) as e:
                logging.error(f"return_date parse error: {e}")
        if "status" in data:
            trip.status = (data["status"] or "").strip() or None
        if "budget" in data:
            try:
                trip.budget = float(data["budget"]) if data["budget"] else 0.0
            except (ValueError, TypeError):
                trip.budget = 0.0
        if "travel_type" in data:
            trip.travel_type = (data["travel_type"] or "").strip() or None
        if "category" in data:
            trip.category = (data["category"] or "").strip() or None
        if "description" in data:
            trip.description = (data["description"] or "").strip() or None
        if "travelers" in data:
            trip.travelers = (data["travelers"] or "").strip() or None

        # Build precise change description
        changes = []
        new_vals = {
            "trip_purpose": trip.trip_purpose,
            "destination": trip.destination,
            "departure_date": str(trip.departure_date) if trip.departure_date else None,
            "return_date": str(trip.return_date) if trip.return_date else None,
            "budget": trip.budget,
            "description": trip.description,
            "travelers": trip.travelers,
        }
        field_labels = {
            "trip_purpose": "trip name",
            "destination": "destination",
            "departure_date": "start date",
            "return_date": "end date",
            "budget": "budget",
            "description": "description",
            "travelers": "travelers",
        }
        for key, label in field_labels.items():
            old_v = old_vals.get(key)
            new_v = new_vals.get(key)
            if old_v != new_v and new_v:
                if key == "budget":
                    changes.append(f"{label} to ${new_v:,.2f}")
                else:
                    changes.append(f"{label} to '{new_v}'")

        # Notify admins or traveler
        if g.user_role != "admin":
            user = db.query(User).filter(User.email == g.user_email).first()
            traveler_name = user.name if user else g.user_email
            trip_label = trip.trip_purpose or trip.destination or "a trip"

            if changes:
                change_str = ", ".join(changes)
                title = f"{traveler_name} changed {change_str}"
                details = change_str
            else:
                title = f"{traveler_name} updated {trip_label}"
                details = None

            _notify_admins(
                db, g.user_email,
                title=title,
                message=title + ".",
                trip_id=trip.id,
            )
            _create_pending_review(
                db, g.user_email, traveler_name,
                title=title,
                review_type="trip", action="updated",
                trip_id=trip.id, details=details,
            )
        else:
            # Admin edited a traveler's trip — notify the traveler
            trip_label = trip.trip_purpose or trip.destination or "your trip"
            traveler = db.query(User).filter(User.email == trip.traveler_email).first()
            first_name = ((traveler.name or "").split(" ")[0] if traveler else "") or "there"
            if changes:
                change_str = ", ".join(changes)
                msg = f"Hi {first_name}, the admin updated your trip {trip_label}: {change_str}."
            else:
                msg = f"Hi {first_name}, the admin made updates to your trip {trip_label}."
            _notify_traveler(
                db, trip.traveler_email,
                title=f"Admin updated your trip — {trip_label}",
                message=msg,
                trip_id=trip.id,
            )

        db.commit()
        db.refresh(trip)

        # Try to sync to Notion
        if trip.notion_page_id:
            try:
                logging.info(f"Notion sync: page_id={trip.notion_page_id}")
                notion_props = {}
                if trip.trip_purpose:
                    notion_props["Trip Purpose "] = {"rich_text": [{"text": {"content": trip.trip_purpose}}]}
                if trip.destination:
                    notion_props["Destination"] = {"rich_text": [{"text": {"content": trip.destination}}]}
                if trip.departure_date:
                    date_val = {"start": trip.departure_date.isoformat()}
                    if trip.return_date:
                        date_val["end"] = trip.return_date.isoformat()
                    notion_props["Travel Period "] = {"date": date_val}
                if trip.travel_type:
                    notion_props["Travel Type"] = {"select": {"name": trip.travel_type}}
                if trip.status:
                    notion_props["Status"] = {"status": {"name": trip.status}}
                logging.info(f"Notion sync props: {notion_props}")
                if notion_props:
                    result = notion.update_page(trip.notion_page_id, notion_props)
                    logging.info(f"Notion update result: {result.get('id', 'no id')} updated successfully")
            except Exception as notion_err:
                logging.error(f"Notion update failed for trip {trip_id}: {notion_err}", exc_info=True)

        return jsonify(trip.to_dict()), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Update trip error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.delete("/trips/<trip_id>")
@require_auth
def delete_trip(trip_id):
    """Delete a trip and all its receipts. Also archives the Notion page."""
    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        if g.user_role != "admin" and trip.traveler_email != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        # Delete all alerts and receipts for this trip
        db.query(Alert).filter(Alert.trip_id == trip_id).delete()
        receipts = db.query(Receipt).filter(Receipt.trip_id == trip_id).all()
        delete_files([r.image_url for r in receipts if r.image_url])
        for receipt in receipts:
            db.delete(receipt)

        # Archive the Notion page if linked
        if trip.notion_page_id:
            try:
                notion.update_page(trip.notion_page_id, {})
                # Notion API: archive by setting archived=True
                url = f"{notion.BASE_URL}/pages/{trip.notion_page_id}"
                notion._request("PATCH", url, json={"archived": True})
                logging.info(f"Notion page archived for trip {trip_id}")
            except Exception as notion_err:
                logging.error(f"Notion archive failed for trip {trip_id}: {notion_err}")

        # Notify admins or traveler
        dest = trip.destination or trip.trip_purpose or "a trip"
        if g.user_role != "admin":
            user = db.query(User).filter(User.email == g.user_email).first()
            traveler_name = user.name if user else g.user_email
            _notify_admins(
                db, g.user_email,
                title=f"{traveler_name} deleted trip to {dest}",
                message=f"{traveler_name} deleted trip to {dest}.",
                trip_id=None,  # trip is about to be deleted
            )
            _create_pending_review(
                db, g.user_email, traveler_name,
                title=f"{traveler_name} deleted trip to {dest}",
                review_type="trip", action="deleted",
            )
        else:
            # Admin deleted a traveler's trip — notify the traveler
            traveler = db.query(User).filter(User.email == trip.traveler_email).first()
            first_name = ((traveler.name or "").split(" ")[0] if traveler else "") or "there"
            _notify_traveler(
                db, trip.traveler_email,
                title=f"Admin deleted your trip to {dest}",
                message=f"Hi {first_name}, the admin has removed your trip to {dest}.",
                trip_id=None,
            )

        db.delete(trip)
        db.commit()
        return jsonify({"status": "deleted"}), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.patch("/receipts/<receipt_id>")
@require_auth
def update_receipt(receipt_id):
    """Admin can edit receipt fields: merchant, total, category, payment_method, meal_type."""
    if g.user_role != "admin":
        return jsonify({"error": "Admin only"}), 403

    data = request.get_json()
    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        if "merchant" in data:
            receipt.merchant = (data["merchant"] or "").strip() or None
        if "total" in data:
            try:
                receipt.total = float(data["total"])
            except (ValueError, TypeError):
                return jsonify({"error": "Invalid total"}), 400
        if "category" in data:
            cat = data["category"]
            if cat and cat not in TRAVEL_CATEGORIES:
                return jsonify({"error": f"Invalid category. Must be one of: {TRAVEL_CATEGORIES}"}), 400
            receipt.travel_category = cat
            receipt.category = cat
        if "payment_method" in data:
            pm = data["payment_method"]
            if pm not in ("personal", "corporate"):
                return jsonify({"error": "payment_method must be 'personal' or 'corporate'"}), 400
            receipt.payment_method = pm
        if "meal_type" in data:
            mt = (data["meal_type"] or "").strip().lower()
            if mt and mt not in VALID_MEAL_TYPES:
                return jsonify({"error": f"meal_type must be one of {VALID_MEAL_TYPES}"}), 400
            receipt.meal_type = mt or None

        # Notify traveler about the edit
        edit_fields = [k for k in ("merchant", "total", "category", "payment_method", "meal_type") if k in data]
        merchant = receipt.merchant or "a receipt"
        traveler = db.query(User).filter(User.email == receipt.user_id).first()
        first_name = ((traveler.name or "").split(" ")[0] if traveler else "") or "there"
        change_str = ", ".join(edit_fields)
        trip_id = receipt.trip_id if receipt.trip_id and db.query(Trip).filter(Trip.id == receipt.trip_id).first() else None
        _notify_traveler(
            db, receipt.user_id,
            title=f"Admin edited your receipt from {merchant}",
            message=f"Hi {first_name}, the admin updated {change_str} on your receipt from {merchant}.",
            trip_id=trip_id,
        )

        db.commit()
        return jsonify(receipt.to_dict()), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.patch("/receipts/<receipt_id>/payment-method")
@require_auth
def update_receipt_payment_method(receipt_id):
    """Update the payment method (personal/corporate) on a receipt."""
    data = request.get_json()
    method = data.get("payment_method")
    if method not in ("personal", "corporate"):
        return jsonify({"error": "payment_method must be 'personal' or 'corporate'"}), 400

    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404
        if g.user_role != "admin" and receipt.user_id != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        receipt.payment_method = method

        # Notify admins
        if g.user_role != "admin":
            user = db.query(User).filter(User.email == g.user_email).first()
            traveler_name = user.name if user else g.user_email
            merchant = receipt.merchant or "a receipt"
            _notify_admins(
                db, g.user_email,
                title=f"{traveler_name} changed payment to {method} for {merchant}",
                message=f"{traveler_name} changed payment to {method} for {merchant}.",
                trip_id=receipt.trip_id,
            )
            _create_pending_review(
                db, g.user_email, traveler_name,
                title=f"{traveler_name} changed payment to {method} for {merchant}",
                review_type="receipt", action="updated",
                trip_id=receipt.trip_id, receipt_id=receipt.id,
            )

        db.commit()
        return jsonify(receipt.to_dict()), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


VALID_MEAL_TYPES = ("breakfast", "lunch", "dinner", "incidentals", "hospitality")

@app.patch("/receipts/<receipt_id>/meal-type")
@require_auth
def update_receipt_meal_type(receipt_id):
    """Update the meal type on a Meals receipt."""
    data = request.get_json()
    meal_type = (data.get("meal_type") or "").strip().lower()
    if meal_type not in VALID_MEAL_TYPES:
        return jsonify({"error": f"meal_type must be one of {VALID_MEAL_TYPES}"}), 400

    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404
        if g.user_role != "admin" and receipt.user_id != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        receipt.meal_type = meal_type

        # Update existing "Receipt Uploaded" alert instead of creating a new one
        if g.user_role != "admin" and receipt.trip_id:
            merchant = receipt.merchant or "a receipt"
            existing_alerts = db.query(Alert).filter(
                Alert.trip_id == receipt.trip_id,
                Alert.type == "traveler_action",
                Alert.title.contains(f"Receipt Uploaded — {merchant}"),
            ).all()
            if existing_alerts:
                for alert in existing_alerts:
                    alert.message = alert.message.rstrip('.') + f". Meal type: {meal_type}."
            else:
                # No existing alert found, create one with meal type included
                user = db.query(User).filter(User.email == g.user_email).first()
                traveler_name = user.name if user else g.user_email
                _notify_admins(
                    db, g.user_email,
                    title=f"{traveler_name} added a receipt from {merchant}",
                    message=f"{traveler_name} uploaded a receipt from {merchant}. Meal type: {meal_type}.",
                    trip_id=receipt.trip_id,
                )
                _create_pending_review(
                    db, g.user_email, traveler_name,
                    title=f"{traveler_name} added a receipt from {merchant}",
                    review_type="receipt", action="uploaded",
                    trip_id=receipt.trip_id, receipt_id=receipt.id,
                    details=f"Meal type: {meal_type}",
                )

        db.commit()
        return jsonify(receipt.to_dict()), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.delete("/receipts/<receipt_id>")
@require_auth
def delete_receipt(receipt_id):
    """Delete a receipt. Subtracts from trip totals and Notion if linked."""
    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        if g.user_role != "admin" and receipt.user_id != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        # Subtract from trip if linked
        if receipt.trip_id and receipt.travel_category:
            trip = db.query(Trip).filter(Trip.id == receipt.trip_id).first()
            if trip:
                _add_to_trip_category(trip, receipt.travel_category, -(receipt.total or 0))
                # Update Notion if trip has a Notion page
                if trip.notion_page_id:
                    try:
                        col = receipt.travel_category
                        new_val = _get_trip_category_value(trip, col)
                        notion.update_expense_column(trip.notion_page_id, col, max(0, new_val))
                        logging.info(f"Notion updated on delete: {col} = {max(0, new_val)} for trip {trip.id}")
                    except Exception as notion_err:
                        logging.error(f"Notion update on delete failed: {notion_err}")

        # Delete image file from Supabase Storage
        if receipt.image_url:
            delete_file(receipt.image_url)

        # Notify admins or traveler
        merchant = receipt.merchant or "a receipt"
        valid_trip_id = receipt.trip_id if receipt.trip_id and db.query(Trip).filter(Trip.id == receipt.trip_id).first() else None
        if g.user_role != "admin":
            user = db.query(User).filter(User.email == g.user_email).first()
            traveler_name = user.name if user else g.user_email
            _notify_admins(
                db, g.user_email,
                title=f"{traveler_name} deleted a receipt from {merchant}",
                message=f"{traveler_name} deleted a receipt from {merchant}.",
                trip_id=valid_trip_id,
            )
            _create_pending_review(
                db, g.user_email, traveler_name,
                title=f"{traveler_name} deleted a receipt from {merchant}",
                review_type="receipt", action="deleted",
                trip_id=valid_trip_id,
            )
        else:
            # Admin deleted a traveler's receipt — notify the traveler
            traveler = db.query(User).filter(User.email == receipt.user_id).first()
            first_name = ((traveler.name or "").split(" ")[0] if traveler else "") or "there"
            _notify_traveler(
                db, receipt.user_id,
                title=f"Admin deleted your receipt from {merchant}",
                message=f"Hi {first_name}, the admin removed your receipt from {merchant}.",
                trip_id=valid_trip_id,
            )

        db.delete(receipt)
        db.commit()
        return jsonify({"status": "deleted"}), 200
    except Exception as e:
        db.rollback()
        logging.error(f"Delete receipt error: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


def _get_trip_category_value(trip, category):
    """Get current value of a specific expense category on a trip."""
    mapping = {
        "Accommodation Cost": trip.accommodation_cost,
        "Flight Cost": trip.flight_cost,
        "Ground Transportation": trip.ground_transportation,
        "Registration Cost": trip.registration_cost,
        "Meals": trip.meals,
        "Other AS Cost": trip.other_as_cost,
    }
    return mapping.get(category, 0) or 0



# =============================================================================
# ADMIN ENDPOINTS
# =============================================================================

@app.get("/admin/departments")
@require_auth
@require_admin
def admin_departments():
    """Department-level expense aggregation (active + upcoming trips only)."""
    db = SessionLocal()
    try:
        today = datetime.utcnow().date()
        all_trips = db.query(Trip).all()
        trips = [
            t for t in all_trips
            if not ((t.return_date or t.departure_date) and (t.return_date or t.departure_date) < today)
        ]

        dept_map = {}
        for trip in trips:
            dept = trip.department or "Unknown"
            if dept not in dept_map:
                dept_map[dept] = {
                    "department": dept,
                    "trip_count": 0,
                    "traveler_emails": set(),
                    "total_expenses": 0.0,
                    "accommodation_cost": 0.0,
                    "flight_cost": 0.0,
                    "ground_transportation": 0.0,
                    "registration_cost": 0.0,
                    "meals": 0.0,
                    "other_as_cost": 0.0,
                }
            d = dept_map[dept]
            d["trip_count"] += 1
            d["traveler_emails"].add(trip.traveler_email)
            d["accommodation_cost"] += trip.accommodation_cost or 0
            d["flight_cost"] += trip.flight_cost or 0
            d["ground_transportation"] += trip.ground_transportation or 0
            d["registration_cost"] += trip.registration_cost or 0
            d["meals"] += trip.meals or 0
            d["other_as_cost"] += trip.other_as_cost or 0

        # Compute total from actual category sums (more reliable than Notion formula)
        for d in dept_map.values():
            d["total_expenses"] = round(
                d["accommodation_cost"] + d["flight_cost"] +
                d["ground_transportation"] + d["registration_cost"] +
                d["meals"] + d["other_as_cost"], 2
            )

        result = []
        for dept_data in dept_map.values():
            dept_data["traveler_count"] = len(dept_data["traveler_emails"])
            del dept_data["traveler_emails"]
            result.append(dept_data)

        result.sort(key=lambda x: x["total_expenses"], reverse=True)
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.get("/admin/analytics")
@require_auth
@require_admin
def admin_analytics():
    """Org-wide analytics: totals, traveler count, category breakdown (active + upcoming trips only)."""
    db = SessionLocal()
    try:
        today = datetime.utcnow().date()
        all_trips = db.query(Trip).all()
        trips = [
            t for t in all_trips
            if not ((t.return_date or t.departure_date) and (t.return_date or t.departure_date) < today)
        ]
        users = db.query(User).filter(User.role == "traveler").count()

        total_expenses = sum(t.total_expenses or 0 for t in trips)
        total_accommodation = sum(t.accommodation_cost or 0 for t in trips)
        total_flight = sum(t.flight_cost or 0 for t in trips)
        total_ground = sum(t.ground_transportation or 0 for t in trips)
        total_registration = sum(t.registration_cost or 0 for t in trips)
        total_meals = sum(t.meals or 0 for t in trips)
        total_other = sum(t.other_as_cost or 0 for t in trips)

        return jsonify({
            "total_expenses": round(total_expenses, 2),
            "trip_count": len(trips),
            "traveler_count": users,
            "category_breakdown": {
                "Accommodation Cost": round(total_accommodation, 2),
                "Flight Cost": round(total_flight, 2),
                "Ground Transportation": round(total_ground, 2),
                "Registration Cost": round(total_registration, 2),
                "Meals": round(total_meals, 2),
                "Other AS Cost": round(total_other, 2),
            },
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.get("/admin/travelers")
@require_auth
@require_admin
def admin_travelers():
    """List all travelers with their total spend."""
    db = SessionLocal()
    try:
        today = datetime.utcnow().date()
        users = db.query(User).all()
        result = []
        for user in users:
            all_user_trips = db.query(Trip).filter(
                db_or(
                    Trip.traveler_email == user.email,
                    Trip.travelers.contains(user.email),
                )
            ).all()
            # Deduplicate by id
            seen = set()
            unique_trips = []
            for t in all_user_trips:
                if t.id not in seen:
                    seen.add(t.id)
                    unique_trips.append(t)
            trips = [
                t for t in unique_trips
                if not ((t.return_date or t.departure_date) and (t.return_date or t.departure_date) < today)
            ]
            total_spend = sum(t.total_expenses or 0 for t in trips)
            result.append({
                **user.to_dict(),
                "trip_count": len(trips),
                "total_spend": round(total_spend, 2),
            })
        result.sort(key=lambda x: x["total_spend"], reverse=True)
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


# =============================================================================
# USER SEARCH (co-traveler autocomplete)
# =============================================================================

@app.get("/users/search")
@require_auth
def search_users():
    """Search users by name or email for co-traveler autocomplete."""
    q = (request.args.get("q") or "").strip()
    if len(q) < 2:
        return jsonify([]), 200

    db = SessionLocal()
    try:
        current_email = g.user_email
        # Broad match: contains query anywhere in name or email
        contains = f"%{q}%"
        users = (
            db.query(User)
            .filter(
                User.email != current_email,
                (User.name.ilike(contains)) | (User.email.ilike(contains)),
            )
            .limit(10)
            .all()
        )
        results = [
            {"name": u.name, "email": u.email, "department": u.department}
            for u in users
        ]
        return jsonify(results), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()



# =============================================================================
# ALERTS
# =============================================================================

def _notify_admins(db, traveler_email, title, message, trip_id=None, alert_type="traveler_action"):
    """Create an alert for every admin so they see traveler activity in real-time."""
    # Clean up extra whitespace from names
    title = " ".join(title.split())
    message = " ".join(message.split())
    for admin_email in ADMIN_EMAILS:
        if admin_email == traveler_email:
            continue  # don't notify yourself
        db.add(Alert(
            id=str(uuid.uuid4()),
            user_email=admin_email,
            trip_id=trip_id,
            type=alert_type,
            title=title,
            message=message,
            status="inbox",
            admin_email=None,  # not admin-initiated
        ))
    # caller is responsible for db.commit()


def _notify_traveler(db, traveler_email, title, message, trip_id=None, alert_type="admin_action"):
    """Create an alert for a traveler when admin makes changes."""
    title = " ".join(title.split())
    message = " ".join(message.split())
    db.add(Alert(
        id=str(uuid.uuid4()),
        user_email=traveler_email,
        trip_id=trip_id,
        type=alert_type,
        title=title,
        message=message,
        status="inbox",
        admin_email=g.user_email,
    ))
    # caller is responsible for db.commit()


def _next_business_day(d):
    """Return the next business day (Mon-Fri) after date d."""
    nbd = d + timedelta(days=1)
    while nbd.weekday() >= 5:  # 5=Sat, 6=Sun
        nbd += timedelta(days=1)
    return nbd


def _cleanup_completed_alerts(db):
    """Delete completed alerts older than 5 days."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=5)
    deleted = db.query(Alert).filter(
        Alert.status == "completed",
        Alert.created_at < cutoff,
    ).delete(synchronize_session=False)
    if deleted:
        db.commit()
        logging.info(f"Cleaned up {deleted} completed alerts older than 5 days")


def _generate_auto_alerts(db):
    """Generate trip-end and pre-travel alerts for all travelers. Called on app startup / scheduled."""
    _cleanup_completed_alerts(db)
    from datetime import date as date_type
    today = date_type.today()

    trips = db.query(Trip).filter(Trip.return_date != None).all()
    for trip in trips:
        # ── Trip End Reminder ──
        # Alert on next business day after return date
        nbd = _next_business_day(trip.return_date)
        if today >= nbd:
            alert_id = f"trip_end_{trip.id}"
            exists = db.query(Alert).filter(Alert.id == alert_id).first()
            if not exists:
                first_name = (trip.traveler_name or "").split(" ")[0] or "there"
                dest = trip.destination or trip.trip_purpose or "your trip"
                db.add(Alert(
                    id=alert_id,
                    user_email=trip.traveler_email,
                    trip_id=trip.id,
                    type="trip_end_reminder",
                    title=f"Submit receipts for {dest}",
                    message=f"Welcome back from {dest}, {first_name}! Please submit all your receipts within the next 15 business days so we can process your travel claim and get your reimbursement started.",
                    status="inbox",
                ))

    # ── Pre-Travel Reminder ──
    upcoming_trips = db.query(Trip).filter(Trip.departure_date != None).all()
    for trip in upcoming_trips:
        dep = trip.departure_date
        days_until = (dep - today).days
        if 0 <= days_until <= 10:
            # Check if traveler has receipts for this trip
            receipt_count = db.query(Receipt).filter(Receipt.trip_id == trip.id).count()
            if receipt_count == 0:
                alert_id = f"pre_travel_{trip.id}"
                exists = db.query(Alert).filter(Alert.id == alert_id).first()
                if not exists:
                    first_name = (trip.traveler_name or "").split(" ")[0] or "there"
                    dest = trip.destination or trip.trip_purpose or "your trip"
                    if days_until == 0:
                        msg = f"Hey {first_name}, your trip to {dest} starts today! Please submit your receipts now so your TAAR can be processed without any delays."
                    elif days_until <= 3:
                        msg = f"Just a heads up, {first_name} — your {dest} trip is only {days_until} days away and we haven't received any receipts yet. Submit them soon so your TAAR doesn't get delayed."
                    else:
                        from datetime import date as _d
                        date_str = dep.strftime("%B %d")
                        msg = f"Hi {first_name}, your trip to {dest} kicks off on {date_str}. It's a good time to start submitting your receipts so your TAAR can be processed in time."

                    db.add(Alert(
                        id=alert_id,
                        user_email=trip.traveler_email,
                        trip_id=trip.id,
                        type="pre_travel_reminder",
                        title=f"Prepare for {dest}",
                        message=msg,
                        status="inbox",
                    ))

    db.commit()


# Run auto-alert generation on startup
try:
    _startup_db = SessionLocal()
    _generate_auto_alerts(_startup_db)
    _startup_db.close()
    logging.info("Auto-alerts generated on startup")
except Exception as e:
    logging.error(f"Auto-alert generation failed: {e}")


# Background scheduler — runs cleanup + auto-alerts every 24 hours
def _daily_scheduler():
    while True:
        threading.Event().wait(86400)  # 24 hours
        try:
            db = SessionLocal()
            _generate_auto_alerts(db)
            db.close()
            logging.info("Daily scheduler: alerts generated & old completed alerts cleaned up")
        except Exception as e:
            logging.error(f"Daily scheduler failed: {e}")

_scheduler_thread = threading.Thread(target=_daily_scheduler, daemon=True)
_scheduler_thread.start()


@app.get("/alerts")
@require_auth
def get_alerts():
    """Fetch all alerts for the logged-in traveler, enriched with trip/receipt data."""
    db = SessionLocal()
    try:
        alerts = (
            db.query(Alert)
            .filter(Alert.user_email == g.user_email)
            .order_by(Alert.created_at.desc())
            .all()
        )
        result = []
        for a in alerts:
            d = a.to_dict()
            # Determine if this is a receipt or trip alert
            title_lower = (a.title or "").lower()
            receipt_keywords = ["receipt", "image attached", "category updated", "payment method", "meal type"]
            is_receipt = any(k in title_lower for k in receipt_keywords)
            d["category"] = "receipt" if is_receipt else "trip"

            # Enrich with trip data
            if a.trip_id:
                trip = db.query(Trip).filter(Trip.id == a.trip_id).first()
                if trip:
                    d["trip_name"] = trip.trip_purpose or trip.destination or "Trip"
                    d["trip_destination"] = trip.destination
                    d["traveler_email"] = trip.traveler_email
                    # Get traveler name
                    traveler = db.query(User).filter(User.email == trip.traveler_email).first()
                    d["traveler_name"] = traveler.name if traveler else trip.traveler_email

                    # For receipt alerts, find the most recent receipt on this trip
                    if is_receipt:
                        # Try to match by merchant name from title
                        merchant_hint = None
                        if "—" in (a.title or ""):
                            merchant_hint = a.title.split("—", 1)[1].strip()
                        elif "-" in (a.title or ""):
                            merchant_hint = a.title.split("-", 1)[1].strip()

                        receipt = None
                        if merchant_hint:
                            receipt = (
                                db.query(Receipt)
                                .filter(Receipt.trip_id == a.trip_id, Receipt.merchant == merchant_hint)
                                .order_by(Receipt.created_at.desc())
                                .first()
                            )
                        if not receipt:
                            receipt = (
                                db.query(Receipt)
                                .filter(Receipt.trip_id == a.trip_id)
                                .order_by(Receipt.created_at.desc())
                                .first()
                            )
                        if receipt:
                            d["receipt_id"] = receipt.id
                            d["receipt_image_url"] = receipt.image_url
                            d["receipt_amount"] = receipt.total
                            d["receipt_merchant"] = receipt.merchant
                    else:
                        # For trip alerts, compute total spent
                        total = db.query(sa_func.coalesce(sa_func.sum(Receipt.total), 0)).filter(
                            Receipt.trip_id == a.trip_id
                        ).scalar()
                        d["trip_total"] = float(total) if total else 0.0

            result.append(d)
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.patch("/alerts/<alert_id>/status")
@require_auth
def update_alert_status(alert_id):
    """Update alert status: inbox, read, or completed."""
    data = request.get_json()
    new_status = (data.get("status") or "").strip().lower()
    if new_status not in ("inbox", "read", "completed"):
        return jsonify({"error": "status must be inbox, read, or completed"}), 400

    db = SessionLocal()
    try:
        alert = db.query(Alert).filter(Alert.id == alert_id).first()
        if not alert:
            return jsonify({"error": "Alert not found"}), 404
        if alert.user_email != g.user_email:
            return jsonify({"error": "Access denied"}), 403

        alert.status = new_status
        db.commit()
        return jsonify(alert.to_dict()), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/receipts/<receipt_id>/approve")
@require_auth
@require_admin
def approve_receipt(receipt_id):
    """Admin approves a receipt — creates an alert for the traveler."""
    data = request.get_json() or {}
    comment = (data.get("comment") or "").strip()

    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        # Find the traveler (user_id stores email)
        user = db.query(User).filter(User.email == receipt.user_id).first()
        if not user:
            return jsonify({"error": "Traveler not found"}), 404

        first_name = (user.name or "").split(" ")[0] or "there"
        merchant = receipt.merchant or "your receipt"

        msg = f"Great news, {first_name}! Your receipt from {merchant} has been approved."
        if comment:
            msg += f"\n\nAdmin comment: \"{comment}\""

        # Find trip for context
        trip_id = receipt.trip_id
        trip = db.query(Trip).filter(Trip.id == trip_id).first() if trip_id else None
        dest = (trip.destination or trip.trip_purpose or "your trip") if trip else "General"

        alert = Alert(
            id=str(uuid.uuid4()),
            user_email=user.email,
            trip_id=trip_id,
            type="receipt_approved",
            title=f"Receipt Approved — {merchant}",
            message=msg,
            status="inbox",
            admin_email=g.user_email,
        )
        db.add(alert)

        # Mark related pending reviews as approved
        db.query(PendingReview).filter(
            PendingReview.receipt_id == receipt_id,
            PendingReview.status == "pending",
        ).update({"status": "approved"})

        db.commit()
        return jsonify({"alert": alert.to_dict(), "receipt": receipt.to_dict()}), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/receipts/<receipt_id>/comment")
@require_auth
@require_admin
def add_receipt_comment(receipt_id):
    """Admin posts a comment on a receipt — creates an alert for the traveler."""
    data = request.get_json()
    comment = (data.get("comment") or "").strip()
    if not comment:
        return jsonify({"error": "comment is required"}), 400

    db = SessionLocal()
    try:
        receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
        if not receipt:
            return jsonify({"error": "Receipt not found"}), 404

        # user_id stores email
        user = db.query(User).filter(User.email == receipt.user_id).first()
        if not user:
            return jsonify({"error": "Traveler not found"}), 404

        first_name = (user.name or "").split(" ")[0] or "there"
        merchant = receipt.merchant or "your receipt"

        alert = Alert(
            id=str(uuid.uuid4()),
            user_email=user.email,
            trip_id=receipt.trip_id,
            type="admin_comment",
            title=f"Note on {merchant}",
            message=f"Admin left a note on your {merchant} receipt: \"{comment}\"",
            status="inbox",
            admin_email=g.user_email,
        )
        db.add(alert)
        db.commit()
        return jsonify(alert.to_dict()), 201
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/trips/<trip_id>/comment")
@require_auth
@require_admin
def add_trip_comment(trip_id):
    """Admin posts a comment on a trip — creates an alert for the traveler."""
    data = request.get_json()
    comment = (data.get("comment") or "").strip()
    if not comment:
        return jsonify({"error": "comment is required"}), 400

    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        first_name = (trip.traveler_name or "").split(" ")[0] or "there"
        dest = trip.destination or trip.trip_purpose or "your trip"

        alert = Alert(
            id=str(uuid.uuid4()),
            user_email=trip.traveler_email,
            trip_id=trip.id,
            type="admin_comment",
            title=f"Note on {dest}",
            message=f"Admin left a note on your {dest} trip: \"{comment}\"",
            status="inbox",
            admin_email=g.user_email,
        )
        db.add(alert)
        db.commit()
        return jsonify(alert.to_dict()), 201
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/trips/<trip_id>/approve")
@require_auth
@require_admin
def approve_trip(trip_id):
    """Admin approves a trip — updates status and creates an alert for the traveler."""
    data = request.get_json() or {}
    comment = (data.get("comment") or "").strip()

    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        trip.status = "Approved"
        db.flush()

        first_name = (trip.traveler_name or "").split(" ")[0] or "there"
        dest = trip.destination or trip.trip_purpose or "your trip"

        msg = f"Great news, {first_name}! Your trip to {dest} has been approved."
        if comment:
            msg += f"\n\nAdmin comment: \"{comment}\""

        alert = Alert(
            id=str(uuid.uuid4()),
            user_email=trip.traveler_email,
            trip_id=trip.id,
            type="trip_approved",
            title=f"Trip Approved — {dest}",
            message=msg,
            status="inbox",
            admin_email=g.user_email,
        )
        db.add(alert)

        # Mark related pending reviews as approved
        db.query(PendingReview).filter(
            PendingReview.trip_id == trip_id,
            PendingReview.status == "pending",
        ).update({"status": "approved"})

        db.commit()
        return jsonify({"alert": alert.to_dict(), "trip": trip.to_dict()}), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/trips/<trip_id>/discard")
@require_auth
@require_admin
def discard_trip(trip_id):
    """Admin discards a trip — deletes it and creates an alert for the traveler."""
    data = request.get_json() or {}
    comment = (data.get("comment") or "").strip()

    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        first_name = (trip.traveler_name or "").split(" ")[0] or "there"
        dest = trip.destination or trip.trip_purpose or "your trip"
        traveler_email = trip.traveler_email
        trip_id_str = str(trip.id)

        msg = f"Hi {first_name}, your trip to {dest} has been discarded by the admin."
        if comment:
            msg += f"\n\nReason: \"{comment}\""

        # Mark trip as discarded (keep it so traveler can see the reason)
        trip.status = "Discarded"
        db.flush()

        alert = Alert(
            id=str(uuid.uuid4()),
            user_email=traveler_email,
            trip_id=trip_id_str,
            type="trip_discarded",
            title=f"Trip Discarded — {dest}",
            message=msg,
            status="inbox",
            admin_email=g.user_email,
        )
        db.add(alert)

        # Mark related pending reviews as approved
        db.query(PendingReview).filter(
            PendingReview.trip_id == trip_id_str,
            PendingReview.status == "pending",
        ).update({"status": "approved"})

        db.commit()
        return jsonify({"alert": alert.to_dict(), "trip": trip.to_dict()}), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/trips/<trip_id>/status-change")
@require_auth
@require_admin
def change_trip_status_alert(trip_id):
    """Admin changes trip status — creates an alert for the traveler."""
    data = request.get_json()
    new_status = (data.get("status") or "").strip()
    if not new_status:
        return jsonify({"error": "status is required"}), 400

    db = SessionLocal()
    try:
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            return jsonify({"error": "Trip not found"}), 404

        old_status = trip.status
        trip.status = new_status
        db.flush()

        first_name = (trip.traveler_name or "").split(" ")[0] or "there"
        dest = trip.destination or trip.trip_purpose or "your trip"

        # Natural language messages per status
        status_messages = {
            # TAAR flow
            "TAAR Sent": (
                f"Hi {first_name}, your TAAR for {dest} has been sent to you. Please review the details, fill in any required information, and submit your receipts so we can keep things moving.",
                f"TAAR Sent — {dest}"
            ),
            "TAAR Reviewed": (
                f"Hi {first_name}, your TAAR for {dest} has been reviewed by the admin. If any receipts are missing or corrections are needed, you'll receive a follow-up comment with details. Please keep an eye out and make any updates as soon as possible.",
                f"TAAR Reviewed — {dest}"
            ),
            "TAAR Processed": (
                f"Great news, {first_name}! Your TAAR for {dest} has been approved and processed by the Business Office. You're all set to travel!",
                f"TAAR Approved — {dest}"
            ),
            # Travel Claim flow
            "TC Sent": (
                f"Hi {first_name}, your Travel Claim for {dest} has been sent to you. Please review the details, attach any remaining receipts, and submit it so we can begin processing your reimbursement.",
                f"TC Sent — {dest}"
            ),
            "TC Pending Review": (
                f"{first_name}, your Travel Claim for {dest} has been received and is now pending review. We'll follow up once the admin has gone through it.",
                f"TC Pending Review — {dest}"
            ),
            "TC Correction Needed": (
                f"Hey {first_name}, your Travel Claim for {dest} needs a few corrections. Please check the admin's comments for details on what needs to be updated and resubmit as soon as possible.",
                f"TC Correction Needed — {dest}"
            ),
            "TC Processed": (
                f"Great news, {first_name}! Your Travel Claim for {dest} has been approved and processed by the Business Office. Reimbursement should hit your account soon.",
                f"TC Approved — {dest}"
            ),
        }

        msg, title = status_messages.get(new_status, (
            f"The status of your {dest} trip has been updated to \"{new_status}\".",
            f"Status Update — {dest}"
        ))

        alert = Alert(
            id=str(uuid.uuid4()),
            user_email=trip.traveler_email,
            trip_id=trip.id,
            type="status_change",
            title=title,
            message=msg,
            status="inbox",
            admin_email=g.user_email,
        )
        db.add(alert)
        db.commit()

        # Sync status to Notion
        if trip.notion_page_id:
            try:
                notion.update_page(trip.notion_page_id, {
                    "Status": {"status": {"name": new_status}}
                })
                logging.info(f"Notion status synced: {trip.notion_page_id} → {new_status}")
            except Exception as notion_err:
                logging.error(f"Notion status sync failed: {notion_err}")

        return jsonify({"alert": alert.to_dict(), "trip": trip.to_dict()}), 201
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/alerts/generate")
@require_auth
def trigger_alert_generation():
    """Manually trigger auto-alert generation (useful for testing)."""
    db = SessionLocal()
    try:
        _generate_auto_alerts(db)
        return jsonify({"message": "Alerts generated"}), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


# =============================================================================
# PENDING REVIEWS (admin-only, separate from traveler alerts)
# =============================================================================

def _create_pending_review(db, traveler_email, traveler_name, title,
                           review_type="trip", action="created",
                           trip_id=None, receipt_id=None, details=None):
    """Create a pending review for every admin."""
    title = " ".join(title.split())  # clean whitespace
    for admin_email in ADMIN_EMAILS:
        if admin_email == traveler_email:
            continue
        db.add(PendingReview(
            id=str(uuid.uuid4()),
            admin_email=admin_email,
            traveler_email=traveler_email,
            traveler_name=traveler_name.strip(),
            trip_id=trip_id,
            receipt_id=receipt_id,
            review_type=review_type,
            action=action,
            title=title,
            details=details,
            status="pending",
        ))


@app.get("/pending-reviews")
@require_auth
def get_pending_reviews():
    """Fetch all pending reviews for the logged-in admin."""
    if g.user_role != "admin":
        return jsonify({"error": "Admin only"}), 403
    db = SessionLocal()
    try:
        reviews = (
            db.query(PendingReview)
            .filter(
                PendingReview.admin_email == g.user_email,
                PendingReview.status == "pending",
            )
            .order_by(PendingReview.created_at.desc())
            .all()
        )
        result = []
        for r in reviews:
            d = r.to_dict()
            # Enrich with trip data
            if r.trip_id:
                trip = db.query(Trip).filter(Trip.id == r.trip_id).first()
                if trip:
                    d["trip_name"] = trip.trip_purpose or trip.destination or "Trip"
                    d["trip_destination"] = trip.destination
                    d["trip_total"] = float(
                        db.query(sa_func.coalesce(sa_func.sum(Receipt.total), 0))
                        .filter(Receipt.trip_id == r.trip_id).scalar() or 0
                    )
            # Enrich receipt data
            if r.receipt_id:
                receipt = db.query(Receipt).filter(Receipt.id == r.receipt_id).first()
                if receipt:
                    d["receipt_image_url"] = receipt.image_url
                    d["receipt_amount"] = receipt.total
                    d["receipt_merchant"] = receipt.merchant
            result.append(d)
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/pending-reviews/<review_id>/approve")
@require_auth
def approve_pending_review(review_id):
    """Admin approves a pending review item."""
    if g.user_role != "admin":
        return jsonify({"error": "Admin only"}), 403
    db = SessionLocal()
    try:
        review = db.query(PendingReview).filter(PendingReview.id == review_id).first()
        if not review:
            return jsonify({"error": "Review not found"}), 404
        review.status = "approved"
        db.commit()

        # Also approve the trip if it has one
        if review.trip_id:
            trip = db.query(Trip).filter(Trip.id == review.trip_id).first()
            if trip and trip.status != "approved":
                trip.status = "approved"
                # Notify the traveler
                traveler = db.query(User).filter(User.email == trip.traveler_email).first()
                first_name = traveler.name.split()[0] if traveler and traveler.name else "Traveler"
                dest = trip.destination or trip.trip_purpose or "your trip"
                db.add(Alert(
                    id=str(uuid.uuid4()),
                    user_email=trip.traveler_email,
                    trip_id=trip.id,
                    type="trip_approved",
                    title=f"Trip Approved — {dest}",
                    message=f"Great news, {first_name}! Your trip to {dest} has been approved.",
                    status="inbox",
                    admin_email=g.user_email,
                ))
                db.commit()

        return jsonify(review.to_dict()), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


@app.post("/pending-reviews/<review_id>/comment")
@require_auth
def comment_pending_review(review_id):
    """Admin adds a comment to a pending review — notifies the traveler."""
    if g.user_role != "admin":
        return jsonify({"error": "Admin only"}), 403
    data = request.get_json()
    comment = (data.get("comment") or "").strip()
    if not comment:
        return jsonify({"error": "Comment is required"}), 400

    db = SessionLocal()
    try:
        review = db.query(PendingReview).filter(PendingReview.id == review_id).first()
        if not review:
            return jsonify({"error": "Review not found"}), 404

        # Send comment as alert to traveler
        db.add(Alert(
            id=str(uuid.uuid4()),
            user_email=review.traveler_email,
            trip_id=review.trip_id,
            type="admin_comment",
            title="Admin Comment",
            message=comment,
            status="inbox",
            admin_email=g.user_email,
        ))
        db.commit()
        return jsonify({"message": "Comment sent"}), 200
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5001))
    app.run(host="0.0.0.0", port=port, debug=True)
