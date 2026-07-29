#!/usr/bin/env python3
"""
Render a meeting prep brief from JSON to email-safe inline-styled HTML.

Reads JSON from stdin, writes HTML brief container to stdout.

JSON schema (all fields optional — missing renders as "—" or empty):
{
  "subtitle": "<Company> · <Meeting type>",
  "meta": {"lifecycle": "...", "renewal_due": "...", "status_label": "..."},
  "no_fmp_dialogue":   true,  // when set, prospect_focus/blockers/next_steps/moves are replaced with a banner
  "snapshot":          [{"label": "...", "value": "..."}, ...],
  "prospect_focus":    [{"label": "...", "value": "..."}, ...],  // Industries, Agency vs Direct, Region
  "blockers":          [{"label": "...", "value": "..."}, ...],  // rendered red when value is real
  "last_meeting_next_steps": {
    "had_steps": true,
    "steps": [{"step": "...", "status": "Done|Partially done|Not done|Unclear", "evidence": "..."}]
  },
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
  --usage-count "8"          // Prospector logins in the last --usage-window days; omit if unknown
  --usage-flag "green"       // red|yellow|green — colors the meta cell
  --usage-window "30"        // days, default 30
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
C_WARN_BG = "#fef6f4"
C_WARN_BORDER = "#f4d6cf"
C_WARN_TEXT = "#a8351a"
C_OK_BG = "#f0f9f4"
C_OK_BORDER = "#cfe7d8"
C_OK_TEXT = "#1b6b3a"


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


def kv_table(rows, highlight_when_present=False):
    """Render label/value rows.

    highlight_when_present: when True, rows whose value is real (not "Not
    found in CRM") render the value column in warning-red. Used for Blockers.
    """
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
        missing = is_missing(value)
        if missing:
            val_color = C_DIM
        elif highlight_when_present:
            val_color = C_WARN_TEXT
        else:
            val_color = C_TEXT
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


def next_step_card(step):
    status = (step.get("status") or "").strip()
    status_norm = status.lower()
    if status_norm == "done":
        bg, border, text = C_OK_BG, C_OK_BORDER, C_OK_TEXT
    elif status_norm in ("partially done", "partial"):
        bg, border, text = C_WARN_BG, C_WARN_BORDER, C_WARN_TEXT
    elif status_norm == "not done":
        bg, border, text = "#fdecec", "#f4c4c4", C_OBJECTION
    else:
        bg, border, text = C_BG, C_BORDER, C_DIM

    status_html = (
        f'<span style="display:inline-block; font-family:{FONT}; font-size:11px; font-weight:600; '
        f'letter-spacing:0.05em; text-transform:uppercase; padding:3px 9px; background-color:{bg}; '
        f'color:{text}; border:1px solid {border}; border-radius:999px;">{esc(status or "Unclear")}</span>'
    )
    return (
        f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" '
        f'style="margin-bottom:10px; background-color:{C_BG}; border:1px solid {C_BORDER}; border-radius:8px;">'
        f'<tr><td style="padding:16px 22px;">'
        f'<div style="margin-bottom:8px;">{status_html}</div>'
        f'<div style="font-family:{FONT}; font-size:14px; line-height:1.5; color:{C_TEXT}; font-weight:500; margin-bottom:6px;">{esc(step.get("step", ""))}</div>'
        f'<div style="font-family:{FONT}; font-size:13px; line-height:1.5; color:{C_MUTED};">{esc(step.get("evidence", ""))}</div>'
        f'</td></tr></table>'
    )


def next_steps_block(data):
    nx = data.get("last_meeting_next_steps") or {}
    steps = nx.get("steps") or []
    if not nx.get("had_steps", False) or not steps:
        return (
            f'<div style="margin-bottom:36px; padding:14px 18px; background-color:{C_BG}; '
            f'border:1px dashed {C_BORDER}; border-radius:8px; font-family:{FONT}; font-size:13px; color:{C_DIM};">'
            f'No explicit next steps were logged in the last interaction.'
            f'</div>'
        )
    return ''.join(next_step_card(s) for s in steps)


def no_fmp_dialogue_banner():
    return (
        f'<div style="margin-bottom:36px; padding:18px 22px; background-color:{C_WARN_BG}; '
        f'border:1px solid {C_WARN_BORDER}; border-radius:8px;">'
        f'<div style="font-family:{FONT}; font-size:11px; font-weight:600; letter-spacing:0.06em; '
        f'text-transform:uppercase; color:{C_WARN_TEXT}; margin-bottom:8px;">No FMP dialogue found</div>'
        f'<div style="font-family:{FONT}; font-size:14px; line-height:1.5; color:{C_BODY};">'
        f'There is no prior dialogue logged for this contact in FileMaker. Treat as a first meeting — '
        f'ask discovery questions on prospect focus, current blockers, and what success looks like, then log dialogue afterwards.'
        f'</div>'
        f'</div>'
    )


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
        ("Lifecycle", meta.get("lifecycle") or "—", C_TEXT),
        ("Renewal Due", meta.get("renewal_due") or "—", C_TEXT),
        ("Interactions", ctx.interactions or meta.get("interactions") or "—", C_TEXT),
        ("Status", meta.get("status_label") or ctx.status or "—", C_TEXT),
    ]

    if ctx.usage_flag:
        usage_color = {"red": C_OBJECTION, "yellow": C_WARN_TEXT, "green": C_OK_TEXT}.get(ctx.usage_flag, C_TEXT)
        usage_value = f'{ctx.usage_count} logins ({ctx.usage_window}d)' if ctx.usage_count is not None else '—'
        cells.append((f'Prospector Usage', usage_value, usage_color))

    n = len(cells)
    meta_html = ''.join(
        f'<td class="meta-cell" width="{100//n}%" style="padding:14px 16px; '
        f'{"border-right:1px solid "+C_BORDER+";" if i < n - 1 else ""} vertical-align:top;">'
        f'<div style="font-family:{FONT}; font-size:11px; font-weight:600; letter-spacing:0.05em; '
        f'text-transform:uppercase; color:{C_DIM}; margin-bottom:4px;">{label}</div>'
        f'<div style="font-family:{FONT}; font-size:14px; font-weight:600; color:{color};">{esc(value)}</div>'
        f'</td>'
        for i, (label, value, color) in enumerate(cells)
    )

    if data.get("no_fmp_dialogue"):
        body = (
            section_head(1, "Meeting Snapshot") + kv_table(data.get("snapshot", [])) +
            no_fmp_dialogue_banner()
        )
    else:
        body = (
            section_head(1, "Meeting Snapshot") + kv_table(data.get("snapshot", [])) +
            section_head(2, "Prospect Focus") + kv_table(data.get("prospect_focus", [])) +
            section_head(3, "Blockers & Challenges") + kv_table(data.get("blockers", []), highlight_when_present=True) +
            section_head(4, "Last Meeting Next Steps") + next_steps_block(data) +
            section_head(5, "Practical Meeting Moves") + meeting_moves(data.get("meeting_moves", []))
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
    p.add_argument("--usage-count", dest="usage_count", default="")
    p.add_argument("--usage-flag", dest="usage_flag", default="")
    p.add_argument("--usage-window", dest="usage_window", default="30")
    args = p.parse_args()
    args.usage_count = int(args.usage_count) if args.usage_count.strip().isdigit() else None
    if args.usage_flag not in ("red", "yellow", "green"):
        args.usage_flag = ""

    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(fallback(f"JSON parse error: {e}", raw))
        return

    print(render(data, args))


if __name__ == "__main__":
    main()
