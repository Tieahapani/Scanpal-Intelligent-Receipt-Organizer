import os
import random
import smtplib
import json
from email.mime.text import MIMEText
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from flask_cors import CORS
import google.generativeai as genai

from azure_ocr import analyze_receipt_azure

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app)

# Configure Gemini
genai.configure(api_key=os.environ["GEMINI_API_KEY"])

CATEGORIES = [
    "Groceries",
    "Food & Drinks",
    "Electronics",
    "Clothing",
    "Entertainment",
    "Utilities",
    "Travel",
    "Office Supplies",
]

# -----------------------------
# HEALTH CHECK
# -----------------------------
@app.get("/health")
def health():
    """Simple health check endpoint"""
    return {"status": "ok", "provider": "azure"}, 200


# -----------------------------
# AZURE RECEIPT ANALYSIS + GEMINI CURRENCY & CATEGORY
# -----------------------------

import logging 
import google.api_core.exceptions 
@app.post("/expense")
def expense():
    file = request.files.get("file")
    if not file:
        return {"error": "no file provided"}, 400

    img = file.read()
    try:
        # Step 1: Azure OCR extracts receipt data
        data = analyze_receipt_azure(img)
        
        # Step 2: Single Gemini call for BOTH currency and category
        merchant = data.get("merchant", "Unknown")
        address = data.get("address", "")
        raw_lines = data.get("raw_lines", [])
        items = [item.get("name", "") for item in data.get("items", []) if item.get("name")]
        total_amount = data.get("total")
        
        prompt = f"""
Analyze this receipt and return TWO things in JSON format:

1. **CURRENCY**: Detect which currency symbol is used
   - Look in the OCR text for symbols: $, ₹, €, £
   - Look for currency codes: USD, INR, EUR, GBP, Rs, Rs.
   - Check the address/location for clues
   - Return ONLY one of these symbols: $, ₹, €, £

2. **CATEGORY**: Classify into exactly ONE category
   - Choose from: {', '.join(CATEGORIES)}
   - Based on merchant name, items purchased, and receipt context
   
Receipt Information:
- Merchant: {merchant}
- Address: {address}
- Total: {total_amount}
- Items: {items}
- OCR Text (first 15 lines):
{chr(10).join(raw_lines[:15])}

Currency Detection Rules:
- If you see $ or USD → return "$"
- If you see ₹ or INR or Rs or Rs. or GSTIN → return "₹"
- If you see € or EUR or VAT (Europe) → return "€"
- If you see £ or GBP → return "£"
- If address indicates India → return "₹"
- If address indicates UK → return "£"
- If address indicates Europe → return "€"
- Default to "$" if unclear

Category Rules:
- Supermarkets, grocery stores → "Groceries"
- Restaurants, cafes, bars → "Food & Drinks"
- Best Buy, Apple Store, tech shops → "Electronics"
- Clothing stores, fashion → "Clothing"
- Movies, games, concerts → "Entertainment"
- Electric, water, internet bills → "Utilities"
- Hotels, flights, gas stations → "Travel"
- Staples, Office Depot → "Office Supplies"

Return ONLY valid JSON in this EXACT format (no markdown, no extra text):
{{
  "currency": "$",
  "category": "Groceries"
}}
"""
        
        # Call Gemini
        model = genai.GenerativeModel("gemini-2.0-flash")
        try:
            response = model.generate_content(prompt)
            logging.info("Gemini call SUCCESS")
        except google.api_core.exceptions.ResourceExhausted as quota_err:  # 429 quota
            full_quota_details = str(quota_err)
            logging.error(f"*** GEMINI QUOTA 429 FULL ERROR: {full_quota_details} ***")
            return {"error": f"Gemini quota exceeded (check logs). Details: {full_quota_details[:300]}..."}, 429
        except Exception as gemini_err:
            logging.error(f"*** GEMINI OTHER ERROR: {str(gemini_err)} ***")
            raise  # Bubbles to outer except
        
        text = response.text.strip()
        
        # Parse JSON response (handle markdown code blocks)
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()
        
        gemini_result = json.loads(text)
        
        # Validate currency
        detected_currency = gemini_result.get("currency", "$")
        if detected_currency not in ['$', '₹', '€', '£']:
            detected_currency = "$"
        
        # Validate category
        detected_category = gemini_result.get("category", "Other")
        if detected_category not in CATEGORIES:
            detected_category = "Other"
        
        # Add to response
        data["currency"] = detected_currency
        data["category"] = detected_category
        
        return jsonify(data), 200
        
    except Exception as e:
        return {"error": str(e)}, 500


# -----------------------------
# EMAIL OTP LOGIC (for reset)
# -----------------------------
otp_store = {}  # temporary in-memory storage

@app.post("/send_otp")
def send_otp():
    """Send OTP to user email for password reset"""
    data = request.get_json()
    target = data.get("target")

    if not target:
        return jsonify({"error": "Email address required"}), 400

    # generate 6-digit OTP
    otp = str(random.randint(100000, 999999))
    otp_store[target] = otp

    try:
        smtp_server = os.getenv("SMTP_SERVER")
        smtp_port = int(os.getenv("SMTP_PORT"))
        smtp_user = os.getenv("SMTP_USER")
        smtp_pass = os.getenv("SMTP_PASS")

        # Compose email
        msg = MIMEText(
            f"Hi,\n\nYour FinPal password reset code is: {otp}\n\n"
            "This code will expire in 10 minutes.\n\n"
            "If you didn't request this, please ignore this email.\n\n"
            "– FinPal Team"
        )
        msg["Subject"] = "FinPal Password Reset Code"
        msg["From"] = smtp_user
        msg["To"] = target

        # Send email
        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.send_message(msg)

        return jsonify({"status": "success", "message": f"OTP sent to {target}"}), 200

    except Exception as e:
        return jsonify({"error": f"Failed to send email: {e}"}), 500


@app.post("/verify_otp")
def verify_otp():
    """Verify OTP entered by user"""
    data = request.get_json()
    target = data.get("target")
    otp = data.get("otp")

    if not target or not otp:
        return jsonify({"error": "Missing email or OTP"}), 400

    if otp_store.get(target) == otp:
        otp_store.pop(target, None)
        return jsonify({"status": "verified"}), 200

    return jsonify({"status": "invalid"}), 400

@app.post("/reset_password")
def reset_password(): 
    """Finalize password reset after OTP verification"""
    data = request.get_json()
    email = data.get("email")
    new_password = data.get("new_password")

    if not email or not new_password:
        return jsonify({"error": "Missing email or new password"}), 400

    try:
        # 🧠 For now, we'll just log or mock it (since there's no database yet)
        # In a real app, this is where you'd update your users table:
        # e.g. users_db[email]["password"] = hash_password(new_password)
        print(f"✅ Password reset for {email}: {new_password}")

        return jsonify({"status": "success", "message": "Password reset successful"}), 200

    except Exception as e:
        return jsonify({"error": f"Failed to reset password: {e}"}), 500


# -----------------------------
# MAIN
# -----------------------------
if __name__ == "__main__":
    port = int(os.getenv("PORT", 5001))
    app.run(host="0.0.0.0", port=port, debug=True)