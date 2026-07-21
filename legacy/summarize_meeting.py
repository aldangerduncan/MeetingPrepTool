import sys
import os
import json
import urllib.request
import re

def get_api_keys():
    keys = {"openai": None}
    for base in [".", "..", "../.."]:
        oa_path = os.path.join(base, ".openai_key")
        if not keys["openai"] and os.path.exists(oa_path):
            with open(oa_path, "r") as f:
                keys["openai"] = f.read().strip()
    return keys

def call_ai(text, keys):
    if not text or not text.strip():
        return ""

    api_key = keys.get("openai")
    if not api_key:
        return "Error: No API Key found."
    url = "https://api.openai.com/v1/chat/completions"
    model = "gpt-4o"

    system_prompt = "You are a helpful assistant. Summarize the following meeting notes into one brief paragraph (max 2 lines)."
    
    data = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text}
        ]
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    
    try:
        req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"), headers=headers)
        with urllib.request.urlopen(req) as response:
            res_json = json.loads(response.read().decode("utf-8"))
            return res_json["choices"][0]["message"]["content"].strip()
    except Exception as e:
        return f"Error calling AI: {e}"

def main():
    if len(sys.argv) > 1:
        text = sys.argv[1]
    else:
        text = sys.stdin.read()
        
    keys = get_api_keys()
    summary = call_ai(text, keys)
    print(summary)

if __name__ == "__main__":
    main()
