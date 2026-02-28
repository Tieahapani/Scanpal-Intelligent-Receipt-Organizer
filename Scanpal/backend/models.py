import os
from dotenv import load_dotenv
from datetime import datetime, timezone, date
from sqlalchemy import create_engine, Column, String, Float, DateTime, Date, Text, JSON, ForeignKey, Integer
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
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    def to_dict(self):
        return {
            "id": self.id,
            "email": self.email,
            "name": self.name,
            "department": self.department,
            "role": self.role,
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
    other_as_cost = Column(Float, default=0.0)
    total_expenses = Column(Float, default=0.0)
    advance = Column(Float, default=0.0)
    claim = Column(Float, default=0.0)
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
            "other_as_cost": self.other_as_cost or 0.0,
            "total_expenses": self.total_expenses or 0.0,
            "advance": self.advance or 0.0,
            "claim": self.claim or 0.0,
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
            "receipt_date": self.receipt_date,
            "items": self.items,
            "ocr_raw": self.ocr_raw,
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
    attempts = Column(Integer, default=0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


def init_db():
    Base.metadata.create_all(engine)
