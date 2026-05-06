#!/usr/bin/env python3
"""
Render a meeting prep brief from JSON to email-safe inline-styled HTML.

Reads JSON from stdin, writes HTML brief container to stdout.

JSON schema (all fields optional — missing renders as "—" or empty):
{
  "subtitle": "<Company> · <Meeting type>",
  "meta": {"lifecycle": "...", "renewal_due": "...", "status_label": "..."},
  "snapshot":          [{"label": "...", "value": "..."}, ...],
  "commercial_read":   {"label": "Bottom line", "paragraphs": ["...", "..."]},
  "stakeholders":      [{"label": "...", "value": "..."}, ...],
  "brand_appetite":    {"<Group name>": ["tag1", "tag2"], ...},
  "agency_buying_path": "<paragraph text>",
  "region_focus":      [{"label": "...", "value": "..."}, ...],
  "value_evidence":    [{"label": "...", "value": "..."}, ...],
  "recommended_angle": {"label": "Open with", "paragraphs": ["...", "..."]},
  "proof_points":      [{"label": "...", "value": "..."}, ...],
  "meeting_moves":     [
    {"title": "...", "rows": [{"label": "Evidence", "value": "..."}, ...]}
  ]
}

CLI flags inject system-side context that the AI doesn't know:
  --name "Toby Brocklehurst"
  --company "St Kilda Saints"
  --interactions "50 recent"
  --status "Active Connector"
  --meeting-intent "Renewal Check-in"
"""

import sys
import json
import argparse
import html as html_lib

FONT = "'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif"
C_TEXT = "#0e1116"
C_BODY = "#1a1d21"
C_MUTED = "#5d6470"
C_DIM = "#8a8f98"
C_BORDER = "#eef0f3"
C_BG = "#fafbfc"
C_ACCENT = "#5e6ad2"
C_ACCENT_BG = "#f0f4ff"
C_ACCENT_BORDER = "#dfe5f5"
C_ACCENT_TEXT = "#4a5dbb"
C_OBJECTION = "#c93838"
C_TAG_BG = "#f5f6f8"
C_TAG_TEXT = "#3d434c"
C_TAG_BORDER = "#e6e8ec"


def esc(s):
    if s is None:
        return ""
    return html_lib.escape(str(s), quote=False)


def is_missing(v):
    if not v:
        return True
    s = str(v).strip().lower()
    return s in ("—", "-", "n/a", "na") or "not found" in s or "not mentioned" in s


def section_head(num, title):
    return (
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:14px;">'
        f'<tr><td style="padding-bottom:14px; border-bottom:1px solid {C_BORDER};">'
        f'<span style="font-family:{FONT}; font-size:11px; font-weight:600; color:{C_DIM}; letter-spacing:0.05em; margin-right:10px;">{num:02d}</span>'
        f'<span style="font-family:{FONT}; font-size:16px; font-weight:600; color:{C_TEXT}; letter-spacing:-0.01em;">{esc(title)}</span>'
        f'</td></tr></table>'
    )


def kv_table(rows):
    if not rows:
        return ""
    out = [
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" '
        f'style="margin-bottom:36px; border:1px solid {C_BORDER}; border-radius:8px; background-color:{C_BG};">'
    ]
    for i, r in enumerate(rows):
        last = (i == len(rows) - 1)
        bb = "" if last else f"border-bottom:1px solid {C_BORDER};"
        label = esc(r.get("label", ""))
        value = r.get("value", "")
        val_color = C_DIM if is_missing(value) else C_TEXT
        out.append(
            f'<tr>'
            f'<td class="kv-label" width="38%" style="padding:11px 16px; {bb} border-right:1px solid {C_BORDER}; '
            f'font-family:{FONT}; font-size:13px; color:{C_MUTED}; font-weight:500; vertical-align:top;">{label}</td>'
            f'<td class="kv-value" style="padding:11px 16px; {bb} font-family:{FONT}; font-size:14px; '
            f'color:{val_color}; vertical-align:top;">{esc(value)}</td>'
            f'</tr>'
        )
    out.append('</table>')
    return ''.join(out)


def callout(label, paragraphs):
    if not paragraphs:
        return ""
    paras = []
    for i, p in enumerate(paragraphs):
        margin = "0" if i == len(paragraphs) - 1 else "0 0 12px 0"
        paras.append(
            f'<p style="margin:{margin}; font-family:{FONT}; font-size:14px; line-height:1.6; color:{C_BODY};">{esc(p)}</p>'
        )
    return (
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" '
        f'style="margin-bottom:36px; background-color:{C_ACCENT_BG}; border:1px solid {C_ACCENT_BORDER}; border-radius:8px;">'
        f'<tr><td style="padding:18px 22px;">'
        f'<div style="font-family:{FONT}; font-size:11px; font-weight:600; letter-spacing:0.06em; '
        f'text-transform:uppercase; color:{C_ACCENT_TEXT}; margin-bottom:10px;">{esc(label)}</div>'
        f'{"".join(paras)}'
        f'</td></tr></table>'
    )


def paragraph(text):
    return (
        f'<p style="margin:0 0 36px 0; font-family:{FONT}; font-size:14px; line-height:1.6; color:{C_BODY};">'
        f'{esc(text)}</p>'
    )


def tag_group(label, items, accent=False):
    if not items:
        return ""
    bg = C_ACCENT_BG if accent else C_TAG_BG
    color = C_ACCENT_TEXT if accent else C_TAG_TEXT
    border = C_ACCENT_BORDER if accent else C_TAG_BORDER
    tags = ''.join(
        f'<span style="display:inline-block; font-family:{FONT}; font-size:13px; padding:5px 11px; '
        f'background-color:{bg}; color:{color}; border:1px solid {border}; border-radius:6px; margin-right:6px;">{esc(t)}</span>'
        for t in items
    )
    return (
        f'<div style="font-family:{FONT}; font-size:11px; font-weight:600; letter-spacing:0.05em; '
        f'text-transform:uppercase; color:{C_DIM}; margin:0 0 8px 0;">{esc(label)}</div>'
        f'<div style="margin-bottom:18px; line-height:2;">{tags}</div>'
    )


def brand_appetite(appetite):
    if not appetite:
        return ""
    out = ['<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" '
           'style="margin-bottom:36px;"><tr><td>']
    keys = list(appetite.keys())
    for i, k in enumerate(keys):
        out.append(tag_group(k, appetite[k] or [], accent=(i == 0)))
    out.append('</td></tr></table>')
    return ''.join(out)


def meeting_move(move):
    title = esc(move.get("title", ""))
    rows = move.get("rows", [])
    row_html = []
    for r in rows:
        label = esc(r.get("label", ""))
        value = esc(r.get("value", ""))
        is_obj = r.get("is_objection") or r.get("label", "").strip().lower() == "objection"
        label_color = C_OBJECTION if is_obj else C_DIM
        row_html.append(
            f'<tr>'
            f'<td class="move-label" width="100" valign="top" style="padding:4px 12px 4px 0; font-family:{FONT}; '
            f'font-size:11px; font-weight:600; letter-spacing:0.05em; text-transform:uppercase; color:{label_color};">{label}</td>'
            f'<td class="move-value" valign="top" style="padding:4px 0; font-family:{FONT}; font-size:14px; '
            f'line-height:1.5; color:{C_BODY};">{value}</td>'
            f'</tr>'
        )
    return (
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" '
        f'style="margin-bottom:10px; background-color:{C_BG}; border:1px solid {C_BORDER}; border-radius:8px;">'
        f'<tr><td style="padding:18px 22px;">'
        f'<div style="font-family:{FONT}; font-size:15px; font-weight:600; color:{C_TEXT}; '
        f'letter-spacing:-0.01em; margin-bottom:14px;">'
        f'<span style="display:inline-block; width:6px; height:6px; background-color:{C_ACCENT}; '
        f'border-radius:50%; margin-right:8px; vertical-align:middle;">&nbsp;</span>{title}</div>'
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">'
        f'{"".join(row_html)}'
        f'</table>'
        f'</td></tr></table>'
    )


def meeting_moves(moves):
    if not moves:
        return ""
    return ''.join(meeting_move(m) for m in moves)


def render(data, ctx):
    name = ctx.name or data.get("contact_name", "")
    subtitle = data.get("subtitle") or (
        f'{ctx.company} · {ctx.meeting_intent}' if ctx.company and ctx.meeting_intent else (ctx.company or "")
    )

    meta = data.get("meta") or {}
    cells = [
        ("Lifecycle", meta.get("lifecycle") or "—"),
        ("Renewal Due", meta.get("renewal_due") or "—"),
        ("Interactions", ctx.interactions or meta.get("interactions") or "—"),
        ("Status", meta.get("status_label") or ctx.status or "—"),
    ]

    meta_html = ''.join(
        f'<td class="meta-cell" width="25%" style="padding:14px 16px; '
        f'{"border-right:1px solid "+C_BORDER+";" if i < 3 else ""} vertical-align:top;">'
        f'<div style="font-family:{FONT}; font-size:11px; font-weight:600; letter-spacing:0.05em; '
        f'text-transform:uppercase; color:{C_DIM}; margin-bottom:4px;">{label}</div>'
        f'<div style="font-family:{FONT}; font-size:14px; font-weight:600; color:{C_TEXT};">{esc(value)}</div>'
        f'</td>'
        for i, (label, value) in enumerate(cells)
    )

    cr = data.get("commercial_read") or {}
    ra = data.get("recommended_angle") or {}

    body = (
        section_head(1, "Meeting Snapshot") + kv_table(data.get("snapshot", [])) +
        section_head(2, "Commercial Read") + callout(cr.get("label", "Bottom line"), cr.get("paragraphs", [])) +
        section_head(3, "Stakeholder Map") + kv_table(data.get("stakeholders", [])) +
        section_head(4, "Brand & Vertical Appetite") + brand_appetite(data.get("brand_appetite") or {}) +
        section_head(5, "Agency & Buying Path") + paragraph(data.get("agency_buying_path") or "Not found in CRM") +
        section_head(6, "Region & Patch Focus") + kv_table(data.get("region_focus", [])) +
        section_head(7, "Prospector Value Evidence") + kv_table(data.get("value_evidence", [])) +
        section_head(8, "Recommended Angle") + callout(ra.get("label", "Open with"), ra.get("paragraphs", [])) +
        section_head(9, "Proof Points") + kv_table(data.get("proof_points", [])) +
        section_head(10, "Practical Meeting Moves") + meeting_moves(data.get("meeting_moves", []))
    )

    return (
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="640" class="container" '
        f'style="width:640px; max-width:640px; background-color:#ffffff; border:1px solid #e6e8ec; '
        f'border-radius:12px; overflow:hidden; margin-bottom:24px;">'
        f'<tr><td class="px" style="padding:40px 44px 28px 44px; border-bottom:1px solid {C_BORDER};">'
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>'
        f'<td style="background-color:{C_ACCENT_BG}; border:1px solid {C_ACCENT_BORDER}; border-radius:999px; '
        f'padding:6px 12px; font-family:{FONT}; font-size:11px; font-weight:600; letter-spacing:0.06em; '
        f'text-transform:uppercase; color:{C_ACCENT_TEXT};">Meeting Brief</td></tr></table>'
        f'<h1 class="brief-h1" style="margin:20px 0 6px 0; font-family:{FONT}; font-size:34px; line-height:1.1; '
        f'font-weight:700; letter-spacing:-0.02em; color:{C_TEXT};">{esc(name)}</h1>'
        f'<p style="margin:0 0 28px 0; font-family:{FONT}; font-size:16px; line-height:1.4; color:{C_MUTED};">{esc(subtitle)}</p>'
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" '
        f'style="border:1px solid {C_BORDER}; border-radius:8px; background-color:{C_BG};">'
        f'<tr>{meta_html}</tr></table>'
        f'</td></tr>'
        f'<tr><td class="px" style="padding:36px 44px 16px 44px;">{body}</td></tr>'
        f'</table>'
    )


def fallback(error_msg, raw):
    snippet = esc(raw[:1500])
    return (
        f'<table role="presentation" width="640" style="background:#fff; padding:24px; border-radius:8px; '
        f'border:1px solid #eef0f3; font-family:{FONT};">'
        f'<tr><td>'
        f'<div style="font-size:14px; color:{C_OBJECTION}; font-weight:600; margin-bottom:8px;">Brief generation failed</div>'
        f'<div style="font-size:13px; color:{C_MUTED}; margin-bottom:12px;">{esc(error_msg)}</div>'
        f'<pre style="background:#f5f6f8; padding:12px; overflow:auto; font-size:11px; '
        f'border-radius:6px; white-space:pre-wrap;">{snippet}</pre>'
        f'</td></tr></table>'
    )


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--name", default="")
    p.add_argument("--company", default="")
    p.add_argument("--interactions", default="")
    p.add_argument("--status", default="")
    p.add_argument("--meeting-intent", dest="meeting_intent", default="")
    args = p.parse_args()

    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(fallback(f"JSON parse error: {e}", raw))
        return

    print(render(data, args))


if __name__ == "__main__":
    main()
