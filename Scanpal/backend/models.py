import os
from dotenv import load_dotenv
from datetime import datetime, timezone, date
from sqlalchemy import create_engine, Column, String, Float, DateTime, Date, Text, JSON, ForeignKey, Integer, Boolean
from sqlalchemy.orm import declarative_base, sessionmaker, relationship
from sqlalchemy.pool import QueuePool

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=5,
    max_overflow=10,
    pool_timeout=30,
    pool_recycle=300,
    pool_pre_ping=True,
)

SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True)
    email = Column(String, unique=True, nullable=False, index=True)
    name = Column(String, nullable=False)
    department = Column(String, nullable=True)
    role = Column(String, default="traveler")  # "traveler" or "admin"
    password_hash = Column(String, nullable=True)  # bcrypt hash, max 8 char password
    remembered = Column(Boolean, default=False)     # True if user checked "Remember Me"
    profile_image = Column(String, nullable=True)   # filename of profile picture
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    def to_dict(self):
        return {
            "id": self.id,
            "email": self.email,
            "name": self.name,
            "department": self.department,
            "role": self.role,
            "profile_image": self.profile_image,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class Trip(Base):
    __tablename__ = "trips"

    id = Column(String, primary_key=True)
    notion_page_id = Column(String, unique=True, nullable=True, index=True)
    traveler_email = Column(String, ForeignKey("users.email"), nullable=False, index=True)
    traveler_name = Column(String, nullable=False)
    department = Column(String, nullable=True)
    trip_purpose = Column(String, nullable=True)
    destination = Column(String, nullable=True)
    departure_date = Column(Date, nullable=True)
    return_date = Column(Date, nullable=True)
    status = Column(String, nullable=True)
    accommodation_cost = Column(Float, default=0.0)
    flight_cost = Column(Float, default=0.0)
    ground_transportation = Column(Float, default=0.0)
    registration_cost = Column(Float, default=0.0)
    meals = Column(Float, default=0.0)
    other_as_cost = Column(Float, default=0.0)
    total_expenses = Column(Float, default=0.0)
    advance = Column(Float, default=0.0)
    claim = Column(Float, default=0.0)
    cover_image_url = Column(Text, nullable=True)
    budget = Column(Float, default=0.0)
    travel_type = Column(String, nullable=True)
    category = Column(String, nullable=True)
    description = Column(Text, nullable=True)
    travelers = Column(Text, nullable=True)
    synced_at = Column(DateTime, nullable=True)

    receipts = relationship("Receipt", back_populates="trip", lazy="dynamic")

    def to_dict(self):
        return {
            "id": self.id,
            "notion_page_id": self.notion_page_id,
            "traveler_email": self.traveler_email,
            "traveler_name": self.traveler_name,
            "department": self.department,
            "trip_purpose": self.trip_purpose,
            "destination": self.destination,
            "departure_date": self.departure_date.isoformat() if self.departure_date else None,
            "return_date": self.return_date.isoformat() if self.return_date else None,
            "status": self.status,
            "accommodation_cost": self.accommodation_cost or 0.0,
            "flight_cost": self.flight_cost or 0.0,
            "ground_transportation": self.ground_transportation or 0.0,
            "registration_cost": self.registration_cost or 0.0,
            "meals": self.meals or 0.0,
            "other_as_cost": self.other_as_cost or 0.0,
            "total_expenses": self.total_expenses or 0.0,
            "advance": self.advance or 0.0,
            "claim": self.claim or 0.0,
            "cover_image_url": self.cover_image_url,
            "budget": self.budget or 0.0,
            "travel_type": self.travel_type,
            "category": self.category,
            "description": self.description,
            "travelers": self.travelers,
            "synced_at": self.synced_at.isoformat() if self.synced_at else None,
        }


class Receipt(Base):
    __tablename__ = "receipts"

    id = Column(String, primary_key=True)
    user_id = Column(String, nullable=False, index=True)
    trip_id = Column(String, ForeignKey("trips.id"), nullable=True, index=True)
    travel_category = Column(String(50), nullable=True)  # One of 5 travel categories
    image_url = Column(Text, nullable=True)
    merchant = Column(String, nullable=True)
    address = Column(String, nullable=True)
    total = Column(Float, nullable=True)
    currency = Column(String(5), default="$")
    category = Column(String(50), nullable=True)  # Legacy generic category
    receipt_date = Column(String, nullable=True)
    items = Column(JSON, nullable=True)
    ocr_raw = Column(JSON, nullable=True)
    payment_method = Column(String(20), default="personal")  # "personal" or "corporate"
    added_by = Column(String(20), default="traveler")  # "traveler" or "admin"
    meal_type = Column(String(20), nullable=True)  # breakfast, lunch, dinner, incidentals, hospitality
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    trip = relationship("Trip", back_populates="receipts")

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "trip_id": self.trip_id,
            "travel_category": self.travel_category,
            "image_url": self.image_url,
            "merchant": self.merchant,
            "address": self.address,
            "total": self.total,
            "currency": self.currency,
            "category": self.category,
            "receipt_date": self.receipt_date or (self.created_at.isoformat() if self.created_at else None),
            "items": self.items,
            "ocr_raw": self.ocr_raw,
            "payment_method": self.payment_method or "personal",
            "added_by": self.added_by or "traveler",
            "meal_type": self.meal_type,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(String, primary_key=True)
    user_email = Column(String, ForeignKey("users.email"), nullable=False, index=True)  # traveler receiving the alert
    trip_id = Column(String, ForeignKey("trips.id"), nullable=True, index=True)
    type = Column(String(30), nullable=False)
    # types: "trip_end_reminder", "pre_travel_reminder", "status_change", "admin_comment"
    title = Column(String, nullable=False)
    message = Column(Text, nullable=False)
    status = Column(String(15), default="inbox")  # "inbox", "read", "completed"
    admin_email = Column(String, nullable=True)  # who triggered it (null for auto-generated)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    trip = relationship("Trip")

    def to_dict(self):
        return {
            "id": self.id,
            "user_email": self.user_email,
            "trip_id": self.trip_id,
            "type": self.type,
            "title": self.title,
            "message": self.message,
            "status": self.status,
            "admin_email": self.admin_email,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class PendingReview(Base):
    __tablename__ = "pending_reviews"

    id = Column(String, primary_key=True)
    admin_email = Column(String, nullable=False, index=True)
    traveler_email = Column(String, nullable=False)
    traveler_name = Column(String, nullable=False)
    trip_id = Column(String, ForeignKey("trips.id"), nullable=True, index=True)
    receipt_id = Column(String, nullable=True)
    review_type = Column(String(20), nullable=False)  # "receipt" or "trip"
    action = Column(String(30), nullable=False)  # "created", "updated", "deleted", "uploaded", etc.
    title = Column(String, nullable=False)  # conversational title
    details = Column(Text, nullable=True)  # extra info (amount, merchant, category, etc.)
    status = Column(String(15), default="pending")  # "pending", "approved", "commented"
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    trip = relationship("Trip")

    def to_dict(self):
        return {
            "id": self.id,
            "admin_email": self.admin_email,
            "traveler_email": self.traveler_email,
            "traveler_name": self.traveler_name,
            "trip_id": self.trip_id,
            "receipt_id": self.receipt_id,
            "review_type": self.review_type,
            "action": self.action,
            "title": self.title,
            "details": self.details,
            "status": self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class OtpCode(Base):
    __tablename__ = "otp_codes"

    id = Column(String, primary_key=True)
    email = Column(String, nullable=False, index=True)
    code = Column(String(6), nullable=False)
    purpose = Column(String(20), nullable=False)  # "login" or "register"
    name = Column(String, nullable=True)           # stored for registration flow
    department = Column(String, nullable=True)     # stored for registration flow
    pending_password = Column(String, nullable=True)  # password to save after OTP verify
    attempts = Column(Integer, default=0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


def init_db():
    Base.metadata.create_all(engine)
    # Add new columns if they don't exist (lightweight migration)
    from sqlalchemy import inspect, text
    insp = inspect(engine)
    existing = {c["name"] for c in insp.get_columns("trips")}
    with engine.begin() as conn:
        if "budget" not in existing:
            conn.execute(text("ALTER TABLE trips ADD COLUMN budget FLOAT DEFAULT 0.0"))
        if "category" not in existing:
            conn.execute(text("ALTER TABLE trips ADD COLUMN category VARCHAR"))
        if "description" not in existing:
            conn.execute(text("ALTER TABLE trips ADD COLUMN description TEXT"))
        if "travelers" not in existing:
            conn.execute(text("ALTER TABLE trips ADD COLUMN travelers TEXT"))
        if "travel_type" not in existing:
            conn.execute(text("ALTER TABLE trips ADD COLUMN travel_type VARCHAR"))
        if "meals" not in existing:
            conn.execute(text("ALTER TABLE trips ADD COLUMN meals FLOAT DEFAULT 0.0"))

    # Receipts table migrations
    receipt_cols = {c["name"] for c in insp.get_columns("receipts")}
    with engine.begin() as conn:
        if "added_by" not in receipt_cols:
            conn.execute(text("ALTER TABLE receipts ADD COLUMN added_by VARCHAR(20) DEFAULT 'traveler'"))

    # Users table migrations
    user_cols = {c["name"] for c in insp.get_columns("users")}
    with engine.begin() as conn:
        if "profile_image" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN profile_image VARCHAR"))

    # Alerts table — create if not exists
    if "alerts" not in insp.get_table_names():
        Alert.__table__.create(engine)
    else:
        alert_cols = {c["name"] for c in insp.get_columns("alerts")}
        with engine.begin() as conn:
            if "admin_email" not in alert_cols:
                conn.execute(text("ALTER TABLE alerts ADD COLUMN admin_email VARCHAR"))
            if "title" not in alert_cols:
                conn.execute(text("ALTER TABLE alerts ADD COLUMN title VARCHAR NOT NULL DEFAULT ''"))
