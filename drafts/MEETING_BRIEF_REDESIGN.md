# Meeting Brief Redesign — Proposal

**Status:** Draft. No live code is changed by this folder. Approve before we touch [meeting_prep.sh](../meeting_prep.sh) / [render_brief.py](../render_brief.py).

## Why change it

The current 10-section brief covers a lot of ground but spreads attention thinly. Several sections (Stakeholder Map, Brand & Vertical Appetite, Proof Points) frequently render as "Not found in CRM" because the underlying FileMaker dialogue rarely names that information explicitly. The result is visual noise on email open without commercial signal.

You said you want the brief to land on three questions every morning:

1. **What type of prospect does this person look for?** — industry/category, agency-vs-direct, regional focus
2. **What's stopping them using Prospector?** — data quality complaints, time-to-be-proactive, other adoption blockers
3. **Were the next steps from the last meeting actioned?** — and if not, why

Plus you want the Practical Meeting Moves kept.

## Proposed structure (5 sections)

| # | Section                  | Source                                   |
|---|--------------------------|------------------------------------------|
| 1 | **Meeting Snapshot**     | Keep — system-injected facts (no LLM hallucination risk) |
| 2 | **Prospect Focus**       | NEW — consolidates current sections 4–6  |
| 3 | **Blockers & Challenges**| NEW — refocus of current section 7       |
| 4 | **Last Meeting Next Steps** | NEW — net-new, mined from dialogue    |
| 5 | **Practical Meeting Moves** | Keep unchanged                        |

### Section detail

**1. Meeting Snapshot** — unchanged. Key/value table: Company, Contact, Meeting type, Lifecycle stage, Relationship, Main risk, Main opportunity.

**2. Prospect Focus** — three labelled rows, all extracted from CRM dialogue:
- **Industries & verticals** (free text, e.g. "QSR, Retail, Banking, Insurance — focus on challenger brands in retail")
- **Agency vs Direct** (free text, e.g. "Direct patch; rarely buys via agencies. Mentioned MediaCom once in 2024 as a partner.")
- **Region / state focus** (free text, e.g. "VIC and NSW only. Has flagged WA expansion ambition but no active patch yet.")

The LLM is told to write *short, specific* values — no padding. Returns "Not mentioned in CRM" if the dialogue doesn't say.

**3. Blockers & Challenges** — three labelled rows, all extracted from dialogue:
- **Data accuracy / freshness complaints** ("Flagged outdated Coles contact in Mar 2026" — or "None raised")
- **Time / proactive use barriers** ("Said in Feb 2026 he hasn't logged in for 6 weeks because he's running too many pitches" — or "None raised")
- **Other blockers** (anything else — pricing pushback, integration, training gaps)

Critically reframed from "Value Evidence" → "What's stopping value". This is the section that drives renewal-risk conversations.

**4. Last Meeting Next Steps** — for each agreed next step from the most recent prior interaction, render a small card:
- **Agreed step** (e.g. "Alex to send 5 sample QSR insights by 15 Mar")
- **Status** (Done / Partially done / Not done / Unclear — inferred from later dialogue)
- **Evidence** (the dialogue line that supports the status)

If no clear next steps were logged last time, the section renders a one-line "No explicit next steps in last interaction" so the reader knows it wasn't omitted.

**5. Practical Meeting Moves** — kept verbatim from current section 10 (cards with Evidence / Question / Example / Objection / Response).

## What goes away

| Dropped section          | Why                                                                                  |
|--------------------------|--------------------------------------------------------------------------------------|
| Commercial Read          | "Bottom line" callout overlaps with Meeting Moves opening question                   |
| Stakeholder Map          | You called this unnecessary — rarely populated in FileMaker, mostly LLM inference   |
| Brand & Vertical Appetite| Rolled into Prospect Focus (industries) as a single tighter row                      |
| Agency & Buying Path     | Rolled into Prospect Focus as the agency-vs-direct row                              |
| Region & Patch Focus     | Rolled into Prospect Focus as the region row                                        |
| Prospector Value Evidence| Reframed and tightened into Blockers & Challenges                                   |
| Recommended Angle        | "Open with" callout overlaps with the first Meeting Move's Question row             |
| Proof Points             | Brand/trigger/search examples surface naturally inside Meeting Moves' Example rows  |

Net: 10 sections → 5. The email gets shorter, more scannable, and more honest about what the CRM actually knows.

## What changes in code (if you approve)

1. **[meeting_prep.sh](../meeting_prep.sh) lines 263–336** — replace the JSON schema with the new 5-section schema (see [draft_render_brief.py](draft_render_brief.py) for shape).
2. **[meeting_prep.sh](../meeting_prep.sh) lines 253–258** — extend CORE RULES with: "For Blockers, only surface explicit complaints found in dialogue — don't infer dissatisfaction from neutral language. For Next Steps Actioned, look at the most recent dialogue first, then scan forward for evidence of follow-through."
3. **[render_brief.py](../render_brief.py) lines 225–235** — replace the 10-section body with the 5-section body. Reuse `section_head()`, `kv_table()`, `meeting_moves()` helpers. One new helper `next_step_card()` (similar to `meeting_move()`).
4. **No FileMaker schema changes needed** — the new fields are all LLM-extracted from the same `Subscriber Dialogues` history we already pull.

## How to review this proposal

1. Read this doc to check the structure matches your intent.
2. Open [sample_brief.html](sample_brief.html) in a browser — synthetic Damien Langley brief rendered in the new format. Compare side-by-side with the live [Key_Contact_Damien_Langley_1780360085.html](../Key_Contact_Damien_Langley_1780360085.html) from 2 June.
3. If happy, tell me to apply changes — I'll edit `meeting_prep.sh` + `render_brief.py`, push, and the GitHub Action deploys to the VPS.
4. If the data flow / sections feel wrong, tell me what's off and I'll update the draft files only.

## Open questions for you

- **Severity colouring?** Right now all kv-table values are neutral grey. Want the Blockers section to render in warning-red when something is found? Easy add.
- **Render mode if dialogue is sparse?** For a brand-new contact with no prior dialogues, all three new sections would render "Not mentioned in CRM". Worth showing a short banner ("First meeting — no prior context") instead of three empty cards? Up to you.
- **Should "Practical Meeting Moves" know about the next-step status?** E.g. if a step is "Not done", auto-bias a Meeting Move toward "ask why X didn't happen". I can wire this into the prompt — flag if you want it.
