import os
import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv

load_dotenv()

SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER")
SMTP_PASS = os.getenv("SMTP_PASS")


def send_otp_email(to_email: str, otp_code: str):
    """Send a 6-digit OTP code to the given email address."""
    subject = "ASGo - Your Verification Code"
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

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = SMTP_USER
    msg["To"] = to_email
    msg.attach(MIMEText(f"Your ASGo verification code is: {otp_code}", "plain"))
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASS)
        server.sendmail(SMTP_USER, to_email, msg.as_string())

    logging.info(f"OTP email sent to {to_email}")
