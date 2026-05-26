#!/usr/bin/env python3
"""Monday Sales Meeting: pick 3 challenger brands from the last 90 days of
Prospector insights (Supabase) and emit a self-contained HTML email body.

Run via RunDailyHuddle.command's Monday branch.  Reads:
  - .supabase_dsn        Postgres connection string
  - .openai_key          OpenAI API key (shared with analyze_prospector_insights.py)
  - .monday_picks_history.json  rolling list of past picks, used to dedupe

Writes:
  - .monday_picks_history.json  appended with today's picks, pruned to 56 days

Output: full HTML email body on stdout (subject is set by the shell wrapper).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from datetime import date, timedelta
from html import escape

import psycopg2

HISTORY_FILE = ".monday_picks_history.json"
DEDUPE_DAYS = 56
WINDOW_DAYS = 90
CANDIDATE_LIMIT = 300
ROLLING_RETENTION_MONTHS = 24

SIGNAL_ACTIVITY_PATTERNS = [
    "%Appointment%",
    "%Launch%",
    "%Expansion%",
    "%Opening%",
    "%Sponsorship%",
    "%Campaign%",
    "%Acquisition%",
    "%Marketing News%",
    "%Financial Result%",
]

SELECTION_CRITERIA = """You are picking 3 challenger brands for Alex to pitch at the Monday sales meeting at IRD Group / Prospector — an advertising-intelligence company that sells data and insights to media agencies, sponsorship sales teams, and brand strategists.

The team wants brands showing signals that they are *about to* commit serious marketing spend: a media review, an agency appointment, a sports sponsorship, a charity partnership, a brand campaign, or some combination.

Prioritise lesser-known challenger brands over household names. Past picks Alex liked:
- Brunetti Classico (new 1,000sqm flagship venue → expect launch advertising within 30 days)
- Drummond Capital Partners (broadening investor access → expect brand-credibility campaign in 30–60 days)
- Equus Energy (ASX debut after $15M IPO → post-IPO awareness burst typical)
- Queensland Hydro (major project approval → stakeholder + recruitment campaigns 4–8 weeks out)
- One Roof (new CEO → repositioning / growth-phase marketing common in professional services)
- Neara (Series D unicorn → high likelihood of agency support for thought leadership and global campaigns)
- BaptistCare (agency-roster milestone → likely open to new pitches)
- Gem-Care Products (category expansion + hiring a Brand & Influencer Partnerships Director → about to scale sponsorships)

Avoid:
- Tier-1 household names (Woolworths, Coles, Cathay Pacific, Telstra) unless the signal is unusually specific
- Pure financial results without a marketing or activation angle
- Routine product launches from established players
- Anything where the brand has already done the obvious media spend (post-launch, post-campaign)

For each pick, you must return:
- id: the candidate's id (integer, exactly as given)
- company: the company name as shown
- industry: a short human industry label
- trigger: one short line describing the signal (≤ 12 words)
- why_this_matters: 2–3 sentences explaining the commercial implication and likely timing
- talking_points: 2–3 short bullets Alex can read aloud in the meeting (specific facts from the insight)

Return ONLY a JSON array of exactly 3 objects, ordered best-first. No prose, no markdown fences."""


def read_file(path: str) -> str | None:
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return f.read().strip()


def load_history() -> list[dict]:
    raw = read_file(HISTORY_FILE)
    if not raw:
        return []
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        print(f"[!] {HISTORY_FILE} unreadable; treating as empty.", file=sys.stderr)
        return []


def prune_history(history: list[dict]) -> list[dict]:
    cutoff = (date.today() - timedelta(days=DEDUPE_DAYS)).isoformat()
    return [h for h in history if h.get("date", "") >= cutoff]


def prune_old_insights(dsn: str) -> int:
    """Delete insights older than the rolling retention window. Returns rows deleted."""
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(
            f"DELETE FROM public.insights "
            f"WHERE publication_date < CURRENT_DATE - INTERVAL '{ROLLING_RETENTION_MONTHS} months'"
        )
        return cur.rowcount


def fetch_candidates(dsn: str, excluded_companies: set[str]) -> list[dict]:
    patterns_sql = " OR ".join(["activity_type ILIKE %s"] * len(SIGNAL_ACTIVITY_PATTERNS))
    excl_clause = ""
    params: list = list(SIGNAL_ACTIVITY_PATTERNS)
    if excluded_companies:
        excl_clause = "AND LOWER(company) NOT IN %s"
        params.append(tuple(c.lower() for c in excluded_companies))
    params.append(CANDIDATE_LIMIT)

    sql = f"""
        SELECT id, company, industry, company_industry, activity_type,
               publication_date, insight_summary, insight, link, protags
        FROM public.insights
        WHERE publication_date >= CURRENT_DATE - INTERVAL '{WINDOW_DAYS} days'
          AND has_opportunity = TRUE
          AND link IS NOT NULL
          AND ({patterns_sql})
          {excl_clause}
        ORDER BY publication_date DESC
        LIMIT %s
    """

    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def call_openai(api_key: str, candidates: list[dict], excluded: list[str]) -> list[dict]:
    lines = []
    for c in candidates:
        summary = (c.get("insight_summary") or "").strip().replace("\n", " ")[:280]
        industry = c.get("industry") or c.get("company_industry") or ""
        lines.append(
            f"[{c['id']}] {c['company']} | {industry} | {c['activity_type']} | "
            f"{c['publication_date']} | {summary}"
        )
    candidate_block = "\n".join(lines)

    excl_block = ", ".join(excluded) if excluded else "(none)"

    user_prompt = (
        f"Candidates (id | company | industry | activity_type | date | summary):\n\n"
        f"{candidate_block}\n\n"
        f"Companies picked in the last {DEDUPE_DAYS} days (DO NOT pick any of these): {excl_block}"
    )

    payload = {
        "model": "gpt-4o",
        "messages": [
            {"role": "system", "content": SELECTION_CRITERIA},
            {"role": "user", "content": user_prompt},
        ],
        "response_format": {"type": "json_object"},
    }
    # gpt-4o with response_format=json_object needs the word "json" in the prompt — it's there.
    # We ask for an array, but the API wants an object. We'll wrap as { "picks": [...] } and unwrap.
    payload["messages"][0]["content"] += '\n\nWrap the JSON array in an object like {"picks": [...]}.'

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read())
    content = body["choices"][0]["message"]["content"]
    parsed = json.loads(content)
    picks = parsed.get("picks") if isinstance(parsed, dict) else parsed
    if not isinstance(picks, list) or len(picks) != 3:
        raise ValueError(f"Expected list of 3 picks, got: {content[:300]}")
    return picks


def merge_links(picks: list[dict], candidates: list[dict]) -> list[dict]:
    by_id = {c["id"]: c for c in candidates}
    merged = []
    for p in picks:
        cid = p.get("id")
        cand = by_id.get(cid)
        if not cand:
            print(f"[!] LLM returned id {cid} not in candidate list; skipping.", file=sys.stderr)
            continue
        p["link"] = cand.get("link") or ""
        p["publication_date"] = cand.get("publication_date").isoformat() if cand.get("publication_date") else ""
        merged.append(p)
    return merged


def render_html(picks: list[dict]) -> str:
    today_label = date.today().strftime("%-d %b %Y")

    cards = []
    for i, p in enumerate(picks, start=1):
        bullets = "".join(f"<li>{escape(b)}</li>" for b in p.get("talking_points", []))
        link_html = (
            f'<a href="{escape(p["link"])}" target="_blank" '
            f'style="color:#e67e22;text-decoration:none;font-weight:600;">View Prospector insight →</a>'
            if p.get("link") else ""
        )
        cards.append(f"""
        <div style="background:#ffffff;border:1px solid #e0e0e0;border-radius:12px;padding:24px;margin-bottom:20px;">
          <div style="font-size:0.85rem;color:#7f8c8d;letter-spacing:0.05em;text-transform:uppercase;margin-bottom:8px;">Pick {i}</div>
          <h2 style="margin:0 0 4px 0;font-size:1.5rem;color:#2c3e50;">{escape(p.get("company", ""))}</h2>
          <div style="color:#7f8c8d;font-size:0.95rem;margin-bottom:16px;"><strong>Industry:</strong> {escape(p.get("industry", ""))}</div>
          <div style="margin-bottom:12px;"><strong style="color:#e67e22;">Trigger:</strong> {escape(p.get("trigger", ""))}</div>
          <div style="margin-bottom:12px;"><strong>Why this matters:</strong><br>{escape(p.get("why_this_matters", ""))}</div>
          <div style="margin-bottom:16px;"><strong>Talking points:</strong><ul style="margin:8px 0 0 0;padding-left:20px;color:#2c3e50;">{bullets}</ul></div>
          {link_html}
        </div>
        """.strip())

    body = "\n".join(cards)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Brands to Watch — {today_label}</title>
</head>
<body style="margin:0;padding:32px;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f6f8;color:#2c3e50;">
<div style="max-width:680px;margin:0 auto;">
  <div style="margin-bottom:24px;">
    <h1 style="margin:0;font-size:1.75rem;color:#2c3e50;">Brands to Watch</h1>
    <div style="color:#7f8c8d;font-size:0.95rem;margin-top:4px;">{today_label} · Monday Sales Meeting · 3 challenger brands</div>
  </div>
  {body}
  <div style="color:#7f8c8d;font-size:0.8rem;margin-top:24px;text-align:center;">
    Selected from {WINDOW_DAYS} days of Prospector insights · GPT-4o · excluding companies picked in the last {DEDUPE_DAYS} days
  </div>
</div>
</body>
</html>"""


def append_history(history: list[dict], picks: list[dict]) -> list[dict]:
    today = date.today().isoformat()
    for p in picks:
        history.append({
            "date": today,
            "company": p.get("company", ""),
            "id": p.get("id"),
            "link": p.get("link", ""),
        })
    return history


def save_history(history: list[dict]) -> None:
    with open(HISTORY_FILE, "w") as f:
        json.dump(history, f, indent=2)


def main() -> int:
    dsn = read_file(".supabase_dsn")
    if not dsn:
        print("[-] .supabase_dsn not found.", file=sys.stderr)
        return 1
    api_key = read_file("../.openai_key") or read_file(".openai_key")
    if not api_key:
        print("[-] OpenAI key not found.", file=sys.stderr)
        return 1

    history = prune_history(load_history())
    excluded = sorted({h["company"] for h in history if h.get("company")})

    pruned = prune_old_insights(dsn)
    if pruned:
        print(f"[*] Pruned {pruned} insights older than {ROLLING_RETENTION_MONTHS} months.", file=sys.stderr)

    print(f"[*] Fetching candidates from last {WINDOW_DAYS} days, excluding {len(excluded)} recent picks...", file=sys.stderr)
    candidates = fetch_candidates(dsn, set(excluded))
    print(f"[*] {len(candidates)} candidates fetched.", file=sys.stderr)

    if len(candidates) < 3:
        print(f"[-] Not enough candidates ({len(candidates)}); aborting.", file=sys.stderr)
        return 1

    print("[*] Asking GPT-4o for 3 picks...", file=sys.stderr)
    picks = call_openai(api_key, candidates, excluded)
    picks = merge_links(picks, candidates)
    if len(picks) < 3:
        print(f"[-] Only {len(picks)} valid picks after id-merge; aborting.", file=sys.stderr)
        return 1

    print("[*] Rendering HTML...", file=sys.stderr)
    html = render_html(picks)

    save_history(append_history(history, picks))
    print(f"[*] Updated {HISTORY_FILE} ({len(history)} total entries).", file=sys.stderr)

    sys.stdout.write(html)
    return 0


if __name__ == "__main__":
    sys.exit(main())
