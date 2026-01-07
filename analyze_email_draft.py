import email
import sys
import os
import io
import requests
from email import policy
from bs4 import BeautifulSoup

# Configuration
OPENROUTER_KEY_FILE = "../.openrouter_key"
EMAIL_FILE = "../DailyHuddle/Your alert has arrived!.eml"

def get_api_key():
    try:
        with open(OPENROUTER_KEY_FILE, "r") as f:
            return f.read().strip()
    except:
        return None

def extract_text_from_eml(file_path):
    with open(file_path, "rb") as f:
        msg = email.message_from_binary_file(f, policy=policy.default)
    
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            cdispo = str(part.get('Content-Disposition'))
            
            if ctype == 'text/plain' and 'attachment' not in cdispo:
                body = part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', errors='ignore')
                break
            elif ctype == 'text/html' and 'attachment' not in cdispo:
                html = part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', errors='ignore')
                soup = BeautifulSoup(html, "html.parser")
                body = soup.get_text(separator="\n")
                break
    else:
        body = msg.get_payload(decode=True).decode(msg.get_content_charset() or 'utf-8', errors='ignore')
        
    return body

def analyze_with_llm(text, api_key):
    # System prompt based on user requirements
    system_prompt = """
    You are an executive assistant analyzing a daily business alert email.
    
    **Your Goal:** Extract exactly 3 interesting insights relevant to the user's criteria.

    **User's Interests (Prioritize these):**
    1. New Business Opportunities: New agencies starting up, new media sellers opening.
    2. New Advertising Campaigns: Big brands, impactful campaigns, award winners.
    3. Growing Brands: Companies raising capital, expanding, or launching new products.

    **Ignore:** General news, politics, fluff, or minor updates.

    **Output Format:**
    Return a bulleted list of exactly 3 insights. 
    Each bullet should be concise (1 sentence header, 1 sentence detail).
    If fewer than 3 relevant items exist, just list what you found.
    """

    user_prompt = f"Here is the email content:\n\n{text[:10000]}" # Truncate to avoid token limits if massive

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    # Using OpenRouter (defaulting to a good model like Llama 3 or similar if unspecified, 
    # but the user mentioned GPT-4o elsewhere. Let's try to use a high quality one).
    # Since I don't know the exact model the user has access to via OpenRouter, 
    # I'll default to a widely available one or use the user's existing config if I can find it.
    # Assuming standard OpenAI format for OpenRouter.
    
    # Inspecting .openrouter_key file location from previous context
    # It seems to be an OpenAI key actually? The file is named .openrouter_key but user mentioned OpenAI API Key in walkthrough.
    # Let's check the file content structure later or assume it's an OpenAI-compatible endpoint.
    # Wait, the tool is called 'MeetingPrepTool', let's check 'meeting_prep.py' to see how it calls the API.
    
    pass 

# I'll pause the script writing to check 'meeting_prep.py' for the correct API URL and Model name.
