import sys
import os
import json
import urllib.request
import re

# Configuration
OPENAI_KEY_FILE = "../.openai_key"  # Relative to MeetingPrepTool
WEB_APP_URL = "https://script.google.com/macros/s/AKfycbxhH0lpZ3tq6KZovVQV8UpJubi74EloknJRQzYfDiV7yfAr585sdw_OGNPzCMkzjAlG/exec"

def get_api_keys():
    keys = {"openai": None, "openrouter": None}
    # OpenRouter
    or_paths = ["../.openrouter_key", ".openrouter_key", "../../.openrouter_key"]
    for path in or_paths:
        if os.path.exists(path):
            with open(path, "r") as f:
                keys["openrouter"] = f.read().strip()
                break
    # OpenAI
    oa_paths = ["../.openai_key", ".openai_key"]
    for path in oa_paths:
        if os.path.exists(path):
            with open(path, "r") as f:
                keys["openai"] = f.read().strip()
                break
    return keys

def strip_html_tags(text):
    # Remove script and style elements
    clean = re.sub(r'<(script|style).*?>.*?</\1>', '', text, flags=re.DOTALL)
    # Remove HTML tags
    clean = re.sub(r'<.*?>', '', clean)
    # Decode HTML entities if needed (basic ones)
    clean = clean.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    return clean

def fetch_email_from_webapp():
    url = f"{WEB_APP_URL}?action=email"
    try:
        # -L follows redirects
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode("utf-8"))
            
            if not data.get("found"):
                return None
            
            return data.get("body", "") # HTML Body
    except Exception as e:
        print(f"Error fetching email from Web App: {e}")
        return None

def call_ai(text, keys):
    if keys.get("openrouter"):
        url = "https://openrouter.ai/api/v1/chat/completions"
        api_key = keys["openrouter"]
        model = "openai/gpt-4o"
    else:
        url = "https://api.openai.com/v1/chat/completions"
        api_key = keys["openai"]
        model = "gpt-4o"
    
    if not api_key:
        return "Error: No API Key found."
    
    # Compress multiple newlines
    text = re.sub(r'\n\s*\n', '\n\n', text)
    
    system_prompt = """
    You are an executive assistant analyzing a daily business alert email.
    
    **Your Goal:** Extract exactly 3 interesting business insights from the content.

    **Prioritize these topics:**
    1. **New Business Opportunities**: New agencies starting up, new media sellers opening.
    2. **New Advertising Campaigns**: Big brands, impactful campaigns, award winners.
    3. **Growing Brands**: Companies raising capital, expanding, or launching new products.

    **Ignore:** General news, politics, fluff, or minor updates.

    **Output Format:**
    Provide the output as raw HTML <div> blocks (no markdown blocks, just the raw HTML string).
    Use this exact structure for each item:

    <div class="insight">
      <span class="tag">Topic Name</span>
      The description text goes here.
    </div>

    Example:
    <div class="insight">
      <span class="tag">New Agency</span>
      "XYZ Creative" launches in Sydney with 3 founding partners.
    </div>
    """
    
    user_prompt = f"Here is the email content:\n\n{text[:12000]}"

    data = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ]
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
        "HTTP-Referer": "https://github.com/alexsheath"
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"), headers=headers)
    
    try:
        with urllib.request.urlopen(req) as response:
            res_json = json.loads(response.read().decode("utf-8"))
            return res_json["choices"][0]["message"]["content"]
    except Exception as e:
        return f"Error calling AI: {e}"

def main():
    keys = get_api_keys()
    if not keys["openai"] and not keys["openrouter"]:
        print("Error: OpenAI or OpenRouter Key not found.")
        sys.exit(1)
        
    # Fetch from Web App
    # print("Fetching email from Gmail...", file=sys.stderr)
    raw_html = fetch_email_from_webapp()
    
    if not raw_html:
        # print("No 'Your alert has arrived!' email found in the last 24h.", file=sys.stderr)
        # print("(This is expected if it hasn't arrived yet today)")
        sys.exit(0)
        
    clean_text = strip_html_tags(raw_html)
    
    if len(clean_text) < 50:
        # print("Error: Extracted text is too short.", file=sys.stderr)
        sys.exit(1)
        
    # print("Analyzing content with AI...", file=sys.stderr)
    insights = call_ai(clean_text, keys)
    print(insights)

if __name__ == "__main__":
    main()
