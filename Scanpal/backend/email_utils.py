import os
import json
import logging
import urllib.request
import urllib.error
from dotenv import load_dotenv

load_dotenv()

BREVO_API_KEY = os.getenv("BREVO_API_KEY")
SENDER_EMAIL = os.getenv("SENDER_EMAIL", "hapanitiea6@gmail.com")
SENDER_NAME = os.getenv("SENDER_NAME", "ASGo")


def send_otp_email(to_email: str, otp_code: str):
    """Send a 6-digit OTP code via Brevo REST API (HTTPS)."""
    html_body = f"""\
<div style="font-family: Arial, sans-serif; max-width: 400px; margin: 0 auto; padding: 20px;">
    <h2 style="color: #46166B;">ASGo Verification</h2>
    <p>Your verification code is:</p>
    <div style="font-size: 32px; font-weight: bold; letter-spacing: 8px;
                color: #46166B; padding: 16px; background: #F5F5F5;
                border-radius: 8px; text-align: center; margin: 16px 0;">
        {otp_code}
    </div>
    <p style="color: #666; font-size: 14px;">
        This code expires in 5 minutes. Do not share it with anyone.
    </p>
</div>"""

    payload = json.dumps({
        "sender": {"name": SENDER_NAME, "email": SENDER_EMAIL},
        "to": [{"email": to_email}],
        "subject": "ASGo - Your Verification Code",
        "htmlContent": html_body,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.brevo.com/v3/smtp/email",
        data=payload,
        headers={
            "api-key": BREVO_API_KEY,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )

    try:
        resp = urllib.request.urlopen(req, timeout=15)
        logging.info(f"OTP email sent to {to_email} via Brevo (status {resp.status})")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logging.error(f"Brevo API error {e.code}: {body}")
        raise Exception(f"Failed to send verification email: {body}")
