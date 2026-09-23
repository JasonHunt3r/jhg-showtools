# The crash hunt — AppKit's layout-loop guard (to 2026-09-23)

From `spec/handoff.md`, moved here unchanged on 2026-09-23 when that file
was retired. The full write-up; `spec/status.md` carries the short
current-knowledge version and points here.

## What the app did

The crash entry under Known issues has been rewritten from the reports:
25 of them, one exception, always at launch, and the builds that crashed
identified by UUID. `ExceptionProbe` now catches the reason string.

## What 25 reports established

- **An intermittent crash: 25 reports on 2026-09-22, still unnamed but
  now well described.** Read from the reports themselves, 2026-09-23.
  - **Always the same exception**, from
    `-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]` —
    AppKit's guard against constraints being invalidated while it is
    already updating them.
  - **Always within twenty seconds of launch**, never mid-edit. This is
    the window's first layout, not something anyone did.
  - **Two paths reach it, one fault.** Nineteen: AppKit's layout engine
    resizes an `NSHostingView` inside `-[NSView layout]`
    (`NSViewActuallyUpdateFrameFromLayoutEngine`), and the hosting view
    answers by invalidating its safe-area insets → constraints. Six:
    SwiftUI's `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`
    reports a new min/max size for a split column *during* the constraints
    pass. Both say the same thing: something in a column whose minimum
    size depends on the width it is given — measurement during layout.
    The "Style" label collapsing at 320pt was the same family.
  - **Six different builds crashed**, matched by each report's binary
    UUID: five test builds and the `~/Applications` copy Jason had been
    using. So it belongs to no one session's changes. `ViewThatFits` is
    cleared — the first crash predates its being added.
  - **The earlier chase proved nothing** and its conclusions were
    withdrawn: aliveness was checked with `pgrep`, so every refused
    crash-relaunch counted as a healthy launch. To test it properly,
    count a launch only when a *window* appears
    (`tools/list-windows.swift`), quit cleanly between trials, and use
    tens of trials.
  - **THE REASON STRING, caught 2026-09-23** by `ExceptionProbe`, in
    `~/Library/Logs/ShowTools-exception.log`. `NSGenericException`:

    > The window has been marked as needing another Update Constraints in
    > Window pass, but it has already had more Update Constraints in
    > Window passes than there are views in the window.

    So it is **AppKit's layout-loop guard**, not a bad frame or a broken
    view: the window cycles through constraint passes without settling
    and AppKit shoots it. The loop is the one the stack always showed —
    `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`
    → `enqueueLayoutInvalidation` → `setNeedsUpdateConstraints` → round
    again. Something in a split column keeps reporting a *new minimum
    size* during the constraints pass, so each pass invalidates the next.
  - **The exception is raised far more often than it crashes.** Eight
    raises in one sitting with the app surviving every one; Jason's crash
    was one raise that happened to be fatal. So a build that doesn't
    crash is not a build that doesn't loop — **count entries in the log,
    not deaths.** That is the measurement this hunt never had.
  - **View ▸ Restore Default Layout provoked it seven times out of
    seven** (2026-09-23), then zero times out of five on the next build,
    with no relevant change between them. **The bursts are real**, and
    they are what made the earlier bisect worthless. Do not conclude
    anything from a run of trials; the log count over a long session is
    the honest measure.
  - Reports are in `~/Library/Logs/DiagnosticReports/ShowTools-*.ips`.
    The suspect is now specific: a SwiftUI column whose minimum width is
    computed from the width it is given. `MainView`'s sidebar carries a
    `.safeAreaInset(edge: .bottom)` and truncating rows, either of which
    could do it. Unproven.
