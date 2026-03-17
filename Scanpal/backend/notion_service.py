import os
import time
import logging
import threading
from collections import deque
from datetime import datetime, timezone

import requests
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)


class NotionService:
    BASE_URL = "https://api.notion.com/v1"
    NOTION_VERSION = "2022-06-28"
    MAX_REQUESTS_PER_SEC = 3

    # Maps travel category names to Notion column names
    # Maps app category names → actual Notion column names
    EXPENSE_COLUMNS = {
        "Accommodation Cost": "Accommodation Cost",
        "Flight Cost": "Flight Cost",
        "Ground Transportation": "Ground Transportation Costs",
        "Registration Cost": "Registration Cost",
        "Other AS Cost": "Other AS Cost",
    }

    def __init__(self, token=None, database_id=None):
        self.token = token or os.getenv("NOTION_TOKEN")
        self.database_id = database_id or os.getenv("NOTION_DATABASE_ID")
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Notion-Version": self.NOTION_VERSION,
            "Content-Type": "application/json",
        }
        # Rate limiter state
        self._lock = threading.Lock()
        self._request_times = deque(maxlen=self.MAX_REQUESTS_PER_SEC)

    # ─── Rate Limiter ───────────────────────────────────────

    def _rate_limit(self):
        """Block until we can make a request within 3 req/sec."""
        with self._lock:
            now = time.monotonic()
            if len(self._request_times) >= self.MAX_REQUESTS_PER_SEC:
                oldest = self._request_times[0]
                elapsed = now - oldest
                if elapsed < 1.0:
                    sleep_time = 1.0 - elapsed + 0.05  # small buffer
                    time.sleep(sleep_time)
            self._request_times.append(time.monotonic())

    def _request(self, method, url, **kwargs):
        """Make a rate-limited request with retry on 429."""
        for attempt in range(5):
            self._rate_limit()
            resp = requests.request(method, url, headers=self.headers, **kwargs)
            if resp.status_code == 429:
                retry_after = int(resp.headers.get("Retry-After", 1))
                logger.warning(f"Notion 429, retrying after {retry_after}s")
                time.sleep(retry_after)
                continue
            if resp.status_code >= 400:
                logger.error(f"Notion {resp.status_code}: {resp.text}")
            resp.raise_for_status()
            return resp.json()
        raise Exception("Notion API: too many retries on 429")

    # ─── Database Queries ───────────────────────────────────

    def query_database(self, filter_obj=None, sorts=None, start_cursor=None):
        """Query the Notion database with optional filter, sorts, pagination."""
        url = f"{self.BASE_URL}/databases/{self.database_id}/query"
        body = {}
        if filter_obj:
            body["filter"] = filter_obj
        if sorts:
            body["sorts"] = sorts
        if start_cursor:
            body["start_cursor"] = start_cursor
        body["page_size"] = 100
        return self._request("POST", url, json=body)

    def get_all_rows(self):
        """Paginate through the entire database, return all rows."""
        all_rows = []
        cursor = None
        while True:
            result = self.query_database(start_cursor=cursor)
            all_rows.extend(result.get("results", []))
            if not result.get("has_more"):
                break
            cursor = result.get("next_cursor")
        return all_rows

    def get_rows_by_email(self, email):
        """Find all rows where the Email property matches."""
        filter_obj = {
            "property": "Email",
            "email": {"equals": email.lower().strip()},
        }
        all_rows = []
        cursor = None
        while True:
            result = self.query_database(filter_obj=filter_obj, start_cursor=cursor)
            all_rows.extend(result.get("results", []))
            if not result.get("has_more"):
                break
            cursor = result.get("next_cursor")
        return all_rows

    def get_page(self, page_id):
        """Fetch a single Notion page by ID."""
        url = f"{self.BASE_URL}/pages/{page_id}"
        return self._request("GET", url)

    def find_notion_user_by_email(self, email):
        """Search Notion workspace users by email. Returns user ID or None."""
        url = f"{self.BASE_URL}/users"
        try:
            result = self._request("GET", url)
            for user in result.get("results", []):
                person = user.get("person", {})
                if person.get("email", "").lower() == email.lower():
                    return user["id"]
        except Exception as e:
            logger.error(f"Failed to search Notion users: {e}")
        return None

    # ─── Write Back to Notion ───────────────────────────────

    def update_page(self, page_id, properties):
        """Update properties on a Notion page."""
        url = f"{self.BASE_URL}/pages/{page_id}"
        return self._request("PATCH", url, json={"properties": properties})

    def update_expense_column(self, page_id, column_name, new_value):
        """Set a specific expense column (number) on a Notion page."""
        if column_name not in self.EXPENSE_COLUMNS:
            raise ValueError(f"Invalid expense column: {column_name}")
        # Map app category name to actual Notion column name
        notion_column = self.EXPENSE_COLUMNS[column_name]
        properties = {
            notion_column: {"number": new_value},
        }
        return self.update_page(page_id, properties)

    def add_to_expense_column(self, page_id, column_name, amount_to_add):
        """Read current value of an expense column and add to it."""
        if column_name not in self.EXPENSE_COLUMNS:
            raise ValueError(f"Invalid expense column: {column_name}")
        notion_column = self.EXPENSE_COLUMNS[column_name]

        # First read the current page
        url = f"{self.BASE_URL}/pages/{page_id}"
        page = self._request("GET", url)
        props = page.get("properties", {})

        current_value = 0.0
        if notion_column in props:
            num_obj = props[notion_column]
            if num_obj.get("type") == "number" and num_obj.get("number") is not None:
                current_value = num_obj["number"]

        new_value = round(current_value + amount_to_add, 2)
        return self.update_expense_column(page_id, column_name, new_value)

    # ─── Parse Notion Row ───────────────────────────────────

    def parse_notion_row(self, row):
        """Convert a Notion page object into a clean Python dict for Trip creation."""
        props = row.get("properties", {})
        page_id = row.get("id", "")

        def get_title(prop):
            title_list = prop.get("title", [])
            return title_list[0]["plain_text"] if title_list else ""

        def get_rich_text(prop):
            rt_list = prop.get("rich_text", [])
            return rt_list[0]["plain_text"] if rt_list else ""

        def get_number(prop):
            return prop.get("number") or 0.0

        def get_select(prop):
            sel = prop.get("select")
            return sel["name"] if sel else None

        def get_email(prop):
            return prop.get("email") or ""

        def get_date_value(prop):
            """Extract a date from a Notion date property."""
            date_obj = prop.get("date")
            if not date_obj:
                return None
            start = date_obj.get("start")
            if not start:
                return None
            try:
                # Notion dates can be "2026-03-05" or "2026-03-05T10:00:00.000-08:00"
                return datetime.fromisoformat(start.replace("Z", "+00:00")).date()
            except (ValueError, AttributeError):
                return None

        def get_date_end(prop):
            """Extract the end date from a Notion date property."""
            date_obj = prop.get("date")
            if not date_obj:
                return None
            end = date_obj.get("end")
            if not end:
                return None
            try:
                return datetime.fromisoformat(end.replace("Z", "+00:00")).date()
            except (ValueError, AttributeError):
                return None

        def get_status(prop):
            """Extract from Notion 'status' type property."""
            s = prop.get("status")
            return s["name"] if s else None

        def get_people_name(prop):
            """Extract first person's name from a 'people' type property."""
            people = prop.get("people", [])
            if not people:
                return ""
            return people[0].get("name", "")

        def get_formula_number(prop):
            """Extract number from a formula property."""
            f = prop.get("formula", {})
            return f.get("number") or 0.0

        # Extract fields — mapped to EXACT Notion column names
        # (column names have trailing spaces in some cases)
        result = {
            "notion_page_id": page_id,
            "request_number": None,
            "status": None,
            "traveler_name": "",
            "email": "",
            "department": None,
            "trip_purpose": None,
            "destination": None,
            "departure_date": None,
            "return_date": None,
            "accommodation_cost": 0.0,
            "flight_cost": 0.0,
            "ground_transportation": 0.0,
            "registration_cost": 0.0,
            "other_as_cost": 0.0,
            "total_expenses": 0.0,
            "advance": 0.0,
            "claim": 0.0,
        }

        for name, prop in props.items():
            prop_type = prop.get("type", "")
            name_stripped = name.strip()

            # Match by exact column name (stripped of whitespace)
            if name_stripped == "#":
                # Title type containing the request number
                result["request_number"] = get_title(prop)
            elif name_stripped == "Travel No":
                result["request_number"] = prop.get("unique_id", {}).get("number")
            elif name_stripped == "Status":
                if prop_type == "status":
                    result["status"] = get_status(prop)
                else:
                    result["status"] = get_select(prop)
            elif name_stripped == "Traveler Name":
                if prop_type == "people":
                    result["traveler_name"] = get_people_name(prop)
                elif prop_type == "title":
                    result["traveler_name"] = get_title(prop)
                else:
                    result["traveler_name"] = get_rich_text(prop)
            elif name_stripped == "Email":
                result["email"] = get_email(prop)
            elif name_stripped == "Department":
                result["department"] = get_select(prop)
            elif name_stripped == "Trip Purpose":
                result["trip_purpose"] = get_rich_text(prop)
            elif name_stripped == "Destination":
                result["destination"] = get_rich_text(prop)
            elif name_stripped == "Travel Period":
                # Single date property with start and end
                result["departure_date"] = get_date_value(prop)
                result["return_date"] = get_date_end(prop) or get_date_value(prop)
            elif name_stripped == "Accommodation Cost":
                result["accommodation_cost"] = get_number(prop)
            elif name_stripped == "Flight Cost":
                result["flight_cost"] = get_number(prop)
            elif name_stripped == "Ground Transportation Costs":
                result["ground_transportation"] = get_number(prop)
            elif name_stripped == "Registration Cost":
                result["registration_cost"] = get_number(prop)
            elif name_stripped == "Other AS Cost":
                result["other_as_cost"] = get_number(prop)
            elif name_stripped == "Total Expense":
                result["total_expenses"] = get_formula_number(prop)
            elif name_stripped == "Total AS Expense":
                # Use this if Total Expense is still 0
                if result["total_expenses"] == 0.0:
                    result["total_expenses"] = get_formula_number(prop)
            elif name_stripped == "Advance Amount":
                result["advance"] = get_number(prop)
            elif name_stripped == "Claim Amount":
                result["claim"] = get_number(prop)

        return result

    # ─── Create Trip Page ────────────────────────────────────

    def create_trip_page(self, traveler_name, email, department, trip_purpose, destination, departure_date=None, return_date=None):
        """Create a new page in the Notion travel database."""
        url = f"{self.BASE_URL}/pages"

        properties = {
            "#": {
                "title": []
            },
            "Status": {
                "status": {"name": "No ODTA Submitted"}
            },
            "Email": {
                "email": email
            },
            "Trip Purpose ": {
                "rich_text": [{"text": {"content": trip_purpose or ""}}]
            },
            "Destination": {
                "rich_text": [{"text": {"content": destination or ""}}]
            },
        }

        # Set "Traveler Name" people property if we can find the Notion user
        notion_user_id = self.find_notion_user_by_email(email)
        if notion_user_id:
            properties["Traveler Name "] = {"people": [{"object": "user", "id": notion_user_id}]}
            logger.info(f"Set Traveler Name for {email} (Notion user {notion_user_id})")
        else:
            logger.info(f"Notion user not found for {email}, skipping Traveler Name")

        if department:
            properties["Department "] = {"select": {"name": department}}

        if departure_date:
            date_prop = {"start": departure_date.isoformat()}
            if return_date:
                date_prop["end"] = return_date.isoformat()
            properties["Travel Period "] = {"date": date_prop}

        # Initialize expense columns to 0
        for notion_col in self.EXPENSE_COLUMNS.values():
            properties[notion_col] = {"number": 0}

        body = {
            "parent": {"database_id": self.database_id},
            "properties": properties,
        }

        return self._request("POST", url, json=body)

    # ─── Sync ───────────────────────────────────────────────

    def sync_all_trips(self):
        """Fetch all rows from Notion, parse them, return list of dicts."""
        rows = self.get_all_rows()
        parsed = []
        for row in rows:
            try:
                parsed.append(self.parse_notion_row(row))
            except Exception as e:
                logger.error(f"Failed to parse Notion row {row.get('id')}: {e}")
        return parsed
