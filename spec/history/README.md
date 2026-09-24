# History

Dated events: what happened, and when. **Never read these for current
rules or current state** — they are kept because they answer "why is it
like this?", and every one of them was true on its date and may not be
now. Current state is `spec/status.md`; rules are `CLAUDE.md`; decisions
are `spec/plan.md`.

| File | What it is | Superseded by |
|---|---|---|
| `2026-09-21-audit.md` | A read-through of the whole codebase, 2026-09-21, with the findings and what was done about them | Its fixes are in the code; nothing here is a live rule |
| `2026-09-21-hands-on.md` | Driving the app by hand against the handoff's "built but not yet tried" list | `spec/status.md` → Still needs Jason's hands |
| `2026-09-21-phase-3.md` | Phase 3 (music and the timeline) as built, step by step | `spec/plan.md` for the decisions |
| `2026-09-22-alpha-test.md` | The alpha test drive: what the demo show is, second by second, and what to look for | The test passed 2026-09-22 (`077568f`) |
| `2026-09-22-day-five.md` | The fifth session: the Xcode port, a video slide's own sound (V1–V5), and video export (E1–E5) with the traps each was found by | `spec/xcode-port.md`, `spec/video-audio.md`, `spec/video-export.md` |
| `2026-09-22-music-steps-6-7.md` | Beat detection (step 6) and rhythm patterns (step 7), planned then built | `spec/plan.md` under "Rhythm patterns" |
| `2026-09-22-phase-3b.md` | Find Similar, Delete by context, Keep One | — |
| `2026-09-22-phase-4-setlist.md` | Setlist export and import, 4a–4d (reordered here into a–d; the handoff had them in the order they were written) | `spec/status.md` for the open risks |
| `2026-09-23-crash-hunt.md` | The intermittent launch crash: 25 reports, the reason string, and why the earlier bisect was worthless | `spec/status.md` carries the short version and points here |
| `2026-09-23-crash-hunt-session2.md` | Same crash, a second session: the methods tried (stack-trace reading, three reverted fix attempts, automated repro counting) and where the repro counting went wrong — read for method, its conclusions are flagged suspect | `spec/status.md`'s Known Issues entry, itself flagged there as unverified against Jason's own hands |
| `2026-09-23-crash-hunt-session3.md` | Same crash, third session: the cause found (SwiftUI's `.inspector()` on Edit Slides), two false leads closed, and the methodology failures named | `spec/edit-slides-inspector-port.md` (the fix) |
| `2026-09-24-crash-hunt-debrief.md` | The crash hunt looked back on, in Jason's words: volunteered design never crash-tested, a latent bug hunted from the newest change backwards, conjecture built on, what ended it, and whether macOS 27 was part of it | `spec/how-we-design.md` holds the lessons |
| `2026-09-24-cloud-planning-aar.md` | After-action review of the cloud planning session: the audit, the anatomy, the renames, windows, simple things fast, conventions, the design manual, PaneKit; what went well and what didn't | `spec/status.md`'s work queue |
| `2026-09-23-docs-restructure-brief.md` | The brief this folder was made from: why the docs had drifted, and the layout Jason approved | Carried out the same day; the result is the current docs |
| `2026-09-23-pan-and-zoom-rename.md` | Ken Burns → Pan and Zoom carried out (168 refs, three shell scripts missed by the first pass), the stale installed app rebuilt, and the confirmed breakage: an export from before this date loses Pan and Zoom silently on re-import | `spec/status.md` carries the short version and points here |

## Where this came from

Everything dated 2026-09-21 or later in this folder except the audit, the
hands-on and the alpha test was one file, `spec/handoff.md`, which had
grown to 773 lines of narrative in the order it was written rather than
the order things happened. It was split up on 2026-09-23 and the parts
moved here **with their wording intact** — the exact phrasing of a
measurement or a trap is the valuable part of them.

Because they were one document, a few of these still say "below" or "see
above" about something that now lives in a different file, and the
2026-09-22 files each describe a state of play that later files change.
That is the nature of the folder: read them as dated notes, not as a
manual.
