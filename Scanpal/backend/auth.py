import os
from functools import wraps
from datetime import datetime, timezone, timedelta

import jwt
from flask import request, jsonify, g
from dotenv import load_dotenv

load_dotenv()

JWT_SECRET = os.getenv("JWT_SECRET", "change-me-in-production")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 72  # Token valid for 3 days

ADMIN_EMAILS = [
    e.strip().lower()
    for e in os.getenv("ADMIN_EMAILS", "").split(",")
    if e.strip()
]


def create_token(user_id, email, role):
    """Create a JWT token for an authenticated user."""
    payload = {
        "sub": user_id,
        "email": email,
        "role": role,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRY_HOURS),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token):
    """Decode and validate a JWT token. Returns payload or raises."""
    return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])


def is_admin_email(email):
    """Check if an email is in the admin list."""
    return email.lower().strip() in ADMIN_EMAILS


def require_auth(f):
    """Decorator: validate JWT token and inject user info into flask.g"""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid Authorization header"}), 401

        token = auth_header[7:]  # Strip "Bearer "
        try:
            payload = decode_token(token)
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401

        g.user_id = payload["sub"]
        g.user_email = payload["email"]
        g.user_role = payload["role"]
        return f(*args, **kwargs)

    return decorated


def require_admin(f):
    """Decorator: require admin role. Must be used after @require_auth."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if g.get("user_role") != "admin":
            return jsonify({"error": "Admin access required"}), 403
        return f(*args, **kwargs)

    return decorated
