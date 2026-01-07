import json
import urllib.request
import urllib.error
import urllib.parse
import argparse
import sys
import os

# Configuration
HOST = "https://fms14.filemakerstudio.com.au"
DATABASE = "IRD Subscribing Contacts"
# Using the session token identified during research. 
# In a production app, this should be generated via a Login call.
DEFAULT_TOKEN = "dcc790a415765bc93c3d1d2a5060a00438e554c6f6cef153754b"

def make_request(url, method="GET", data=None, token=None):
    headers = {
        "Content-Type": "application/json"
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    if data:
        json_data = json.dumps(data).encode("utf-8")
    else:
        json_data = None

    req = urllib.request.Request(url, data=json_data, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            return json.loads(body)
        except:
            return {"messages": [{"code": str(e.code), "message": str(e)}]}

def find_contact(query_input, token):
    layout = "Data Entry Screen"
    url = f"{HOST}/fmi/data/v1/databases/{urllib.parse.quote(DATABASE)}/layouts/{urllib.parse.quote(layout)}/_find"
    
    # Strategy 1: Exact Email
    if "@" in query_input:
        print(f"[*] Trying Exact Email Match: {query_input}")
        body = {
            "query": [{"Email": f"=={query_input}"}],
            "limit": 1
        }
        res = make_request(url, "POST", body, token)
        if res.get("messages", [{}])[0].get("code") == "0":
            return res["response"]["data"][0]
            
        print(f"[*] Trying Wildcard Email Match: *{query_input}*")
        body = {
            "query": [{"Email": f"*{query_input}*"}],
            "limit": 1
        }
        res = make_request(url, "POST", body, token)
        if res.get("messages", [{}])[0].get("code") == "0":
            return res["response"]["data"][0]

    # Strategy 2: Friendlier Name Search (First Last)
    # Split by space
    parts = query_input.strip().split(" ")
    if len(parts) >= 2:
        print(f"[*] Trying Name Match: {parts[0]} {parts[1]}")
        body = {
            "query": [{
                "First Name": parts[0],
                "Surname": parts[1]
            }],
            "limit": 1
        }
        res = make_request(url, "POST", body, token)
        if res.get("messages", [{}])[0].get("code") == "0":
            return res["response"]["data"][0]
            
    # Strategy 3: Just Surname? (Optional, maybe too broad)
    
    return None

def get_dialogues(subscriber_id, token):
    layout = "Subscriber Dialogues"
    url = f"{HOST}/fmi/data/v1/databases/{urllib.parse.quote(DATABASE)}/layouts/{urllib.parse.quote(layout)}/_find"
    
    print(f"[*] Fetching Dialogues for Subscriber ID: {subscriber_id}")
    body = {
        "query": [{"Subscriber ID": f"={subscriber_id}"}],
        "limit": 50,
        "sort": [{"fieldName": "Contact Date", "sortOrder": "descend"}]
    }
    
    res = make_request(url, "POST", body, token)
    if res.get("messages", [{}])[0].get("code") == "0":
        return res["response"]["data"]
    return []

def main():
    parser = argparse.ArgumentParser(description="Meeting Preparation Tool")
    parser.add_argument("query", help="Name or Email of the contact")
    parser.add_argument("--token", default=DEFAULT_TOKEN, help="FileMaker Data API Token")
    
    args = parser.parse_args()
    
    print(f"--- Meeting Prep Tool: Searching for '{args.query}' ---")
    
    contact = find_contact(args.query, args.token)
    
    if not contact:
        print("[-] Contact NOT FOUND.")
        print("    Troubleshooting: Check spelling or try a broader search.")
        return

    field_data = contact["fieldData"]
    sub_id = field_data.get("ID")
    name = f"{field_data.get('First Name')} {field_data.get('Surname')}"
    email = field_data.get("Email")
    company = field_data.get("Company")
    
    print(f"[+] Found Contact: {name} | {email} | {company}")
    print(f"    Subscriber ID: {sub_id}")
    
    if not sub_id:
        print("[-] Error: Contact found but missing Subscriber ID.")
        return

    dialogues = get_dialogues(sub_id, args.token)
    print(f"[+] Found {len(dialogues)} dialogue records.")
    print("\n" + "="*60)
    print(f"MEETING PREPARATION BRIEF: {name.upper()}")
    print("="*60 + "\n")
    
    print(f"Subject: {name} ({company})\n")
    
    if not dialogues:
        print("No interaction history recorded.")
    else:
        print("Recent Interactions:\n")
        for d in dialogues:
            data = d["fieldData"]
            date = data.get("Contact Date", "Unknown Date")
            manager = data.get("Account Manager", "Unknown")
            content = data.get("Dialogue", "").replace("\r", "\n").strip()
            
            print(f"--- [ {date} ] by {manager} ---")
            print(f"{content}\n")
    
    print("="*60)
    print("Use the text above this line as context for your LLM summarization.")

if __name__ == "__main__":
    main()
