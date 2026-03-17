import os
import logging
import json
import uuid
import secrets
import bcrypt
from datetime import datetime, timezone, timedelta

from flask import Flask, request, jsonify, g, send_file
from dotenv import load_dotenv
from flask_cors import CORS
import google.generativeai as genai
import google.api_core.exceptions

from rag.ingest import load_index, build_index, FAISS_INDEX_PATH
from rag.chat import ask as rag_ask 

from models import SessionLocal, User, Trip, Receipt, OtpCode, init_db, engine
from notion_service import NotionService
from auth import create_token, require_auth, require_admin, is_admin_email
from azure_ocr import analyze_receipt_azure
from email_utils import send_otp_email
from unsplash import fetch_destination_image

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app)

logging.basicConfig(level=logging.INFO)

init_db()

# Add password_hash column if missing (migration for existing DBs)
from sqlalchemy import inspect as sa_inspect, text as sa_text
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

# Upload directory for receipt images
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)


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
                        # Ensure traveler_name is set — fall back to User name
                        if not parsed.get("traveler_name"):
                            parsed["traveler_name"] = user.name
                        _upsert_trip(db, parsed, email)
                    db.commit()
                else:
                    _sync_trips_from_notion(db, g.user_email)
            except Exception as sync_err:
                logging.error(f"Pull-to-refresh sync failed: {sync_err}")

        if g.user_role == "admin":
            # Exclude past trips (return_date or departure_date before today)
            today = datetime.utcnow().date()
            all_trips = db.query(Trip).order_by(Trip.departure_date.desc()).all()
            trips = [
                t for t in all_trips
                if not ((t.return_date or t.departure_date) and (t.return_date or t.departure_date) < today)
            ]
        else:
            trips = (
                db.query(Trip)
                .filter(Trip.traveler_email == g.user_email)
                .order_by(Trip.departure_date.desc())
                .all()
            )
        return jsonify([t.to_dict() for t in trips]), 200
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
        # Get user info
        user = db.query(User).filter(User.email == g.user_email).first()
        if not user:
            return jsonify({"error": "User not found"}), 404

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
            traveler_email=g.user_email,
            traveler_name=user.name,
            department=user.department,
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
        # Notion is source of truth for financial fields
        existing.traveler_name = parsed.get("traveler_name") or existing.traveler_name
        existing.department = parsed.get("department") or existing.department
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
        if parsed.get("status") and not existing.status:
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


def _sync_trips_from_notion(db, email):
    """Full bidirectional sync: upsert Notion trips and remove deleted ones."""
    notion_rows = notion.get_rows_by_email(email)

    # Upsert all trips found in Notion
    user = db.query(User).filter(User.email == email).first()
    notion_page_ids = set()
    for row in notion_rows:
        parsed_trip = notion.parse_notion_row(row)
        # Fall back to User name if Notion doesn't provide traveler_name
        if not parsed_trip.get("traveler_name") and user:
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
            # Also delete associated receipts
            receipts = db.query(Receipt).filter(Receipt.trip_id == trip.id).all()
            for r in receipts:
                if r.image_url:
                    image_path = os.path.join(UPLOAD_DIR, r.image_url)
                    if os.path.exists(image_path):
                        os.remove(image_path)
                db.delete(r)
            db.delete(trip)
            logging.info(f"Removed trip {trip.id} (Notion page {trip.notion_page_id} no longer exists)")

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
            response = model.generate_content(prompt)
            logging.info("Gemini call SUCCESS")
        except google.api_core.exceptions.ResourceExhausted as quota_err:
            logging.error(f"GEMINI QUOTA 429: {quota_err}")
            return jsonify({"error": f"Gemini quota exceeded: {str(quota_err)[:300]}"}), 429
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

        # Save receipt image
        receipt_id = str(uuid.uuid4())
        image_filename = f"{receipt_id}.jpg"
        image_path = os.path.join(UPLOAD_DIR, image_filename)
        with open(image_path, "wb") as f:
            f.write(img)

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

        db.commit()
        return jsonify({"status": "confirmed", "receipt": receipt.to_dict()}), 200

    except Exception as e:
        db.rollback()
        logging.error(f"Confirm error: {e}")
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
            return jsonify({"error": "Access denied"}), 403

        if not receipt.image_url:
            return jsonify({"error": "No image available"}), 404

        image_path = os.path.join(UPLOAD_DIR, receipt.image_url)
        if not os.path.exists(image_path):
            return jsonify({"error": "Image file not found"}), 404

        return send_file(image_path, mimetype="image/jpeg")
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
            old_path = os.path.join(UPLOAD_DIR, user.profile_image)
            if os.path.exists(old_path):
                os.remove(old_path)

        # Save new image
        ext = os.path.splitext(file.filename)[1] or ".jpg"
        filename = f"profile_{user.id}{ext}"
        filepath = os.path.join(UPLOAD_DIR, filename)
        file.save(filepath)

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
            old_path = os.path.join(UPLOAD_DIR, user.profile_image)
            if os.path.exists(old_path):
                os.remove(old_path)
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

        image_path = os.path.join(UPLOAD_DIR, user.profile_image)
        if not os.path.exists(image_path):
            return jsonify({"error": "Image file not found"}), 404

        return send_file(image_path, mimetype="image/jpeg")
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
            query = query.filter(Receipt.user_id == g.user_email)

        if trip_filter:
            query = query.filter(Receipt.trip_id == trip_filter)

        receipts = query.order_by(Receipt.created_at.desc()).all()
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

        if g.user_role != "admin" and trip.traveler_email != g.user_email:
            return jsonify({"error": "Access denied"}), 403

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

        # Delete all receipts for this trip (and their image files)
        receipts = db.query(Receipt).filter(Receipt.trip_id == trip_id).all()
        for receipt in receipts:
            if receipt.image_url:
                image_path = os.path.join(UPLOAD_DIR, receipt.image_url)
                if os.path.exists(image_path):
                    os.remove(image_path)
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

        db.delete(trip)
        db.commit()
        return jsonify({"status": "deleted"}), 200
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

        # Delete image file
        if receipt.image_url:
            image_path = os.path.join(UPLOAD_DIR, receipt.image_url)
            if os.path.exists(image_path):
                os.remove(image_path)

        db.delete(receipt)
        db.commit()
        return jsonify({"status": "deleted"}), 200
    except Exception as e:
        db.rollback()
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
# REPORT SUMMARY (Gemini)
# =============================================================================

@app.post("/report/summary")
@require_auth
def report_summary():
    """Generate an AI expense summary via Gemini. Keeps the API key server-side."""
    data = request.get_json(force=True)
    prompt = data.get("prompt", "")
    if not prompt:
        return jsonify({"error": "prompt is required"}), 400

    try:
        model = genai.GenerativeModel("gemini-2.0-flash")
        response = model.generate_content(
            prompt,
            generation_config=genai.types.GenerationConfig(
                temperature=0.4,
                max_output_tokens=500,
            ),
        )
        return jsonify({"summary": response.text.strip()}), 200
    except Exception as e:
        logging.error(f"Gemini report summary error: {e}")
        return jsonify({"error": str(e)}), 500


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
        users = db.query(User).filter(User.role == "traveler").all()
        result = []
        for user in users:
            all_user_trips = db.query(Trip).filter(Trip.traveler_email == user.email).all()
            trips = [
                t for t in all_user_trips
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
# RAG CHAT
# =============================================================================

_vectorstore = None

def _get_vectorstore():
    global _vectorstore
    if _vectorstore is None:
        if os.path.exists(FAISS_INDEX_PATH):
            _vectorstore = load_index()
        else:
            _vectorstore = build_index()
    return _vectorstore


@app.route('/chat', methods=['POST'])
@require_auth
def chat_endpoint():
    data = request.get_json()
    question = data.get('question', '').strip()
    if not question:
        return jsonify({"error": "No question provided"}), 400

    db = SessionLocal()
    try:
        user = db.query(User).filter_by(email=g.user_email).first()
        trips = db.query(Trip).filter_by(traveler_email=g.user_email).all()
        trip_data = [t.to_dict() for t in trips]

        vs = _get_vectorstore()
        answer = rag_ask(
            question=question,
            vectorstore=vs,
            user_name=user.name.split(' ')[0] if user else None,
            trip_data=trip_data,
        )

        return jsonify({"answer": answer})
    except Exception as e:
        logging.error(f"Chat error: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5001))
    app.run(host="0.0.0.0", port=port, debug=True)
