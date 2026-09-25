# ShowTools — Documentation Hygiene

Sep 25, 2026 · @Jason Hunter

Checked the repo (`github.com/JasonHunt3r/jhg-showtools`) directly against its own docs. Do this pass first, before triaging the separate feedback/bug list — some of that feedback may turn out to be testing against a stale build or reading stale docs.

1. **Resolved — the stale-build question.** `spec/status.md` now confirms `~/Applications/ShowTools.app` was reinstalled off HEAD on 2026-09-25 (commit `6583b99`), so it's current again. One loose end from that swap: BGTools' desktop extension (`BGToolsControls.appex`) was killed rather than relaunched, on Jason's own call, and needs re-enabling by hand before BGTools' desktop features work again — worth doing before testing BGTools specifically.
2. **P1 — `conventions.md` has at least three stale "not built" claims, confirmed against source:**
   - "Open Library Panel… greyed out" — actually wired (`MainView.swift:210`)
   - "Replace Image… on the inspector… deferred, not built" — actually wired (`SlideInspector.swift:100`); `status.md` itself notes the deferred flag was lifted, but `conventions.md`'s own table was never updated to match
   - "⌥-click a row handle opens/closes every drawer — not built" — actually built (`StorylineView.swift:718-726`)

   Root cause: the most recent docs-audit commit (`c6793e0`) fixed staleness in `CLAUDE.md`, `anatomy.md`, `layout.md`, `panekit.md`, `windows.md`, but never touched `conventions.md`. Worth a full pass over `conventions.md`'s per-target table against source, not just these three, since the audit's method (grep the code, not just re-read the doc) is what caught them.
3. **P2 — `status.md` violates its own rule.** It's 916 lines, almost entirely dated session narrative, despite its own header saying "this file is rewritten, not appended to: if a line has a date and a story, it belongs in `history/`." Split the current-state summary from the historical play-by-play — move dated "done 2026-09-24: …" entries into a `spec/history/` file — before it grows further and gets harder to trust at a glance.
