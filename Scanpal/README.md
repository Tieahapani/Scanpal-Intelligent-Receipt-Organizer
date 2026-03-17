# ASGo - Intelligent Travel Expense Manager

<p align="center">
  <img src="assets/asgo_logo.jpeg" alt="ASGo Logo" width="120"/>
</p>

<p align="center">
  <strong>AI-powered travel expense tracking for corporate teams</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?logo=python" alt="Python"/>
  <img src="https://img.shields.io/badge/Flask-REST_API-000000?logo=flask" alt="Flask"/>
  <img src="https://img.shields.io/badge/Notion-Integration-000000?logo=notion" alt="Notion"/>
</p>

---

## Overview

ASGo is a mobile-first corporate travel expense management app. Travelers scan receipts, which are automatically categorized using AI, assigned to trips, and synced to Notion databases. Admins get full visibility into department-level spending analytics.

## Features

### Receipt Management
- **AI-Powered OCR** - Dual-engine scanning using Azure Document Intelligence + Google Gemini as fallback for merchant detection
- **Auto-Categorization** - Receipts are automatically classified into travel categories: Accommodation, Ground Transportation, Meals, Registration, Flight Cost, and Other AS Cost
- **Payment Method Tracking** - Track personal vs corporate (AS Amex) card usage per receipt
- **Multi-Currency Support** - Automatic currency detection via Gemini

### Trip Management
- Create and manage business trips with destination, dates, and budgets
- Assign receipts to trips with automatic expense rollup
- View per-trip spending breakdown by category
- Travel calendar with trip timeline visualization

### Analytics Dashboard
- **Period Filtering** - Weekly, Monthly, and Yearly spending views
- **Payment Method Split** - Personal vs AS Amex breakdown with percentage
- **Category Breakdown** - Interactive donut chart with per-category totals
- **Comparison Metrics** - Dollar-based comparison against previous periods
- **PDF Report Generation** - Download and share expense reports via WhatsApp, Email, AirDrop, etc.

### Admin Panel
- Department-level analytics and spending overview
- Receipt management across all travelers
- Traveler activity monitoring

### Authentication
- Email-based OTP authentication
- Role-based access (Traveler / Admin)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Mobile App** | Flutter (Dart) |
| **Backend API** | Python Flask |
| **Database** | SQLAlchemy (SQLite / PostgreSQL) |
| **External DB** | Notion API (expense tracking) |
| **OCR Engine** | Azure Document Intelligence (prebuilt-receipt) |
| **AI/LLM** | Google Gemini (categorization, merchant fallback, currency detection) |
| **Charts** | fl_chart |
| **PDF Reports** | dart `pdf` package |
| **Sharing** | share_plus (native share sheet) |

## Project Structure

```
Scanpal/
├── lib/
│   ├── main.dart                  # App entry point
│   ├── traveler_home_page.dart    # Main tab controller
│   ├── analytics_page.dart        # Analytics dashboard
│   ├── trip_detail_page.dart      # Trip detail with receipts
│   ├── receipts_page.dart         # Receipt list with filters
│   ├── receipt_detail_page.dart   # Receipt scanning & editing
│   ├── add_trip_page.dart         # Create new trip
│   ├── trips_page.dart            # Trip list
│   ├── login_page.dart            # Auth flow
│   ├── admin_home_page.dart       # Admin dashboard
│   ├── admin_analytics_page.dart  # Admin analytics
│   ├── models/
│   │   ├── trip.dart              # Trip model
│   │   ├── user.dart              # User model
│   │   └── trip_alert.dart        # Alert model
│   └── services/
│       ├── analytics_service.dart # Analytics data processing
│       └── report_service.dart    # PDF report generation
├── backend/
│   ├── app.py                     # Flask API (routes, OCR, Gemini)
│   ├── models.py                  # SQLAlchemy models
│   ├── auth.py                    # Authentication & OTP
│   ├── azure_ocr.py               # Azure Document Intelligence
│   ├── notion_service.py          # Notion API integration
│   ├── email_utils.py             # Email/OTP delivery
│   ├── unsplash.py                # Trip cover images
│   └── requirements.txt           # Python dependencies
└── assets/
    └── asgo_logo.jpeg             # App logo
```

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Python 3.11+
- Azure Document Intelligence API key
- Google Gemini API key
- Notion API integration token

### Backend Setup

```bash
cd backend
pip install -r requirements.txt

# Set environment variables
export AZURE_ENDPOINT=<your-azure-endpoint>
export AZURE_KEY=<your-azure-key>
export GEMINI_API_KEY=<your-gemini-key>
export NOTION_TOKEN=<your-notion-token>
export NOTION_DATABASE_ID=<your-database-id>

python app.py
```

### Flutter Setup

```bash
cd Scanpal
flutter pub get
flutter run
```

Update the API base URL in `lib/env.dart` to point to your backend.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/login` | Send OTP to email |
| POST | `/verify-otp` | Verify OTP and authenticate |
| GET | `/trips` | List user's trips |
| POST | `/trips` | Create a new trip |
| POST | `/scan` | Upload and OCR a receipt |
| GET | `/receipts` | List receipts with filters |
| GET | `/analytics` | Traveler analytics data |
| GET | `/admin/analytics` | Admin department analytics |

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│ Flutter App  │────>│  Flask API   │────>│  Notion Database │
│  (Mobile)    │<────│  (Backend)   │<────│  (Expense Sync)  │
└─────────────┘     └──────┬───────┘     └─────────────────┘
                           │
                    ┌──────┴───────┐
                    │              │
              ┌─────┴─────┐ ┌─────┴─────┐
              │   Azure   │ │  Gemini   │
              │  OCR API  │ │  AI API   │
              └───────────┘ └───────────┘
```

---

<p align="center">Built with Claude Code</p>
