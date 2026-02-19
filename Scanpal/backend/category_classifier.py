import os 
from dotenv import load_dotenv 
load_dotenv()

import google.generativeai as genai 
from fastapi import APIRouter 
from pydantic import BaseModel 
from typing import List 

router = APIRouter() 

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

class ClassifyRequest(BaseModel):
    merchant: str 
    items: List[str]
    raw_lines: List[str]

@router.post("/classify_category")
def classify(req: ClassifyRequest): 
    prompt = f"""
You are an expert system that categorized receipts. 

Your task:
- Analyze the merchant name
- Analyze the individual items
- Analyze the OCR raw text
- Choose EXACTLY ONE category from this list: {CATEGORIES}

Rules:
- Always choose the MOST accurate category
- If multiple categories match, choose the strongest match
- If nothing fits, return "Other"
- Return ONLY the category name, no extra text.



    Merchant: {req.merchant}
    Items: {req.items}
    OCR Text: {req.raw_lines}

    Now respond with ONLY one of: {CATEGORIES}.
    """

    response = genai.GenerativeModel("gemini-2.5-flash").generate_content(prompt)
    category = response.text.strip()

    if category not in CATEGORIES:
        category = "Other"

    return {"category": category}
        

