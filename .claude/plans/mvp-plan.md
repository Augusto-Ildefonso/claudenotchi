# Claudenotchi: pixel companion in the macOS notch

## Context
A native macOS app that shows a pixel-art Claude Code mascot in the notch and reacts live to Claude Code sessions: thinking, coding, needs input, done, error, or an idle activity chosen at random. Open source on GitHub. The design is done in Figma first, then the app is built.

## Decisions (from interview)
- **Source:** Claude Code CLI only, through hooks. Multiple parallel sessions are not required for v1, but the event model carries a `session_id` so they can be added later.
- **Character:** Claude Code's orange pixel mascot as the base. The app is open source, so verify the branding before release and keep the sprites swappable.
- **Stack:** native Swift, SwiftUI plus AppKit (`NSPanel` at the notch position).
- **UI:** compact pill beside the notch. It expands on hover or when attention is needed.
- **On "needs input":** alert animation, expanded pill with the message, 8-bit sound, Approve/Deny buttons, click to focus the terminal.
- **Extras:** celebration when a task finishes, usage/context/cost meter, error reaction, tool-specific animations (coding, reading, bash, web search).
- **Idle:** starts with "waiting", then picks randomly every 30-90s from waiting, video game, tennis. After 5+ minutes of inactivity it sleeps.
- **Hooks:** the app auto-installs them into `~/.claude/settings.json`, with a backup and a one-click uninstall.
- **Displays:** notch Macs, plus a fake notch-style pill at top-center on notchless or external screens.
- **Pixel art:** 16px character in the collapsed pill, 32px art in the expanded view, nearest-neighbor scaling, limited palette.

## Phase 1: Figma (no code yet)
Use the Figma MCP (`use_figma`; load the `figma:figma-use` skill first, and `figma-generate-design` for the layouts).
1. New Figma file "Claudenotchi" with pages: Concept, Characters, States, Specs.
2. **Concept page:** MacBook top-edge frames showing the notch in these states: collapsed, hover-expanded, attention (permission prompt with Approve/Deny), done, and the non-notch fallback.
3. **Characters page:** a 16x16 base mascot on a pixel grid and a palette swatch. Then variations: thinking, coding (typing at a tiny laptop), reading, running bash, web search, alert, celebrating, error/dizzy, waiting, video game (console and controller), tennis (racket and ball), sleeping (zzz). Each state gets 4-8 frames on a sprite-sheet strip. The 32px expanded versions of the key states are drawn here too.
4. **States page:** a state-machine diagram (FigJam via `generate_diagram`) that maps hook events to states.
5. **Review gate:** you approve the visuals before any code is written.

## Phase 2: Architecture (Swift)
- **HookHelper:** a small CLI, called by Claude Code hooks, that writes a JSON event to a Unix domain socket (`~/Library/Application Support/Claudenotchi/sock`).
- **EventServer:** the app's socket listener that decodes events into `SessionEvent` (`session_id`, `type`, `tool`, `message`, `cwd`, `timestamp`).
- **StateMachine:** a pure, testable reducer that turns `SessionEvent` into `CompanionState`.
  - `UserPromptSubmit` → thinking
  - `PreToolUse` → tool state, by tool name: Edit/Write → coding, Read/Grep → reading, Bash → bash, WebSearch/WebFetch → web
  - `Notification` or `PermissionRequest` → needsInput
  - `Stop` → done, then idle after about 5s
  - Tool failure → error
  - A timer drives the idle activities and sleep.
- **IdleScheduler:** random activity every 30-90s (injectable RNG and clock for tests).
- **NotchWindowController:** a borderless `NSPanel` at the screen's notch (`NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea`), with a fallback pill for notchless screens. Handles hover expansion and spaces/fullscreen behavior.
- **SpriteRenderer:** loads sprite sheets (PNG exported from Figma), plays frame animations with nearest-neighbor scaling, and keeps a data-driven manifest (state → frames, fps).
- **PermissionBridge:** a blocking `PermissionRequest` hook. The helper waits on the socket for the app's Approve/Deny reply and prints the hook decision JSON.
- **TerminalFocuser:** on click, activates the terminal app. Start with `cwd` plus the owning terminal PID, via AppleScript or Accessibility for Terminal, iTerm2 and Ghostty.
- **UsageMeter:** reads the transcript JSONL path from the hook payload to compute context %, tokens and cost.
- **SoundPlayer:** 8-bit chimes for needs-input and done, with a mute setting.
- **HookInstaller:** merges hook entries into `~/.claude/settings.json` without clobbering existing hooks, backs up the file, and can uninstall. Marks its entries so they can be found again.
- **Settings:** a menu bar item (sound, launch at login, display choice, uninstall hooks).

## Phase 3: Milestones
1. Xcode project scaffold and a notch panel with a static sprite.
2. Socket + HookHelper + state machine with unit tests, driven by a fake event script.
3. Sprite renderer wired to the exported Figma assets for all states.
4. Hooks installer and a real Claude Code session end to end.
5. Attention flow: expand, sound, Approve/Deny, focus terminal.
6. Idle scheduler and sleep.
7. Usage meter, polish, fallback screens, multi-display.
8. OSS release: README, GIFs, license, signed and notarized build, Homebrew cask later.

## Verification
- Unit tests for StateMachine and IdleScheduler (fake clock/RNG), the HookInstaller merge (existing hooks preserved, uninstall restores), and event decoding.
- Manual: `scripts/fake-session.sh` emits events for every state, and each one is checked on a notch Mac and on an external display.
- End to end: run a real `claude` session and check thinking → coding → needsInput (approve and deny from the notch) → done → idle rotation → sleep.
- Check that the denied permission is actually enforced in Claude Code.

## Open items to settle during design
- App name and final mascot branding (the Claude Code mascot is Anthropic's, so check before an open-source release).
- Whether multi-session is v1 or v2.
- Exact palette and the sprite sheet export format.

## Progress
Figma file (NovoEu team): https://www.figma.com/design/5RQdeqh1HhnijoECcGSbi0/Claudenotchi

Phase 1 (started 2026-10-15):
- [x] Pages created: Concept, Characters, States, Specs
- [x] Palette as Figma variables (`Palette` collection, 10 colors)
- [x] Characters: base 16x16 mascot plus palette swatches
- [x] Characters: sprite sheet v1 with 12 states x 2 frames (waiting, thinking, coding, reading, bash, web, alert, celebrating, error, videogame, tennis, sleeping)
- [x] Concept: 5 notch mockups (collapsed, hover-expanded, attention, done, no-notch fallback)
- [x] State-machine diagram (FigJam, separate file): https://www.figma.com/board/8qjtNVmw20BFUyHUOQ1whI
- [x] Polish sprites (sheet v2): raised arms, racket fully in frame, bigger laptop, terminal, book, globe, controller
- [x] Every state has 4-6 frames with an fps (54 frames of 16px total, see Specs manifest)
- [x] 32px expanded art for key states: waiting, thinking, alert, celebrating (done), error, sleeping (2 frames each)
- [x] States page: hook event to state table with sprite thumbnails and priority/timer rules (the FigJam diagram stays a separate file, linked from the page)
- [x] Specs page: pixel grid, palette, panel geometry, sprite manifest, export format
- [x] Concept mockups updated to v2 sprites (16px in collapsed and fallback, 32px art in hover, attention and done)
- [x] Waiting is now an 8-frame walk cycle @ 6 fps: steps a little to the right, back to center, blink, steps left (Specs manifest updated)
- [ ] Known gaps to decide at review: Figma sprite frames have a dark presentation fill, so export strips must be generated from the pixel maps (not stored in the repo yet)
- [ ] Review gate: user approves visuals before any Swift code

Phase 1 review gate: approved by the user on 2026-10-15.

Phase 2 / Milestone 1 (Xcode scaffold + notch panel with a static sprite), 2026-10-15:
- [x] Xcode project (created by the user, lives in `Claudenotchi/Claudenotchi`, own git repo) converted to macOS-only: deployment target 14.0, app sandbox off (needs `~/.claude/settings.json` and a Unix socket), `LSUIElement` (no Dock icon), bundle id `dev.claudenotchi.Claudenotchi` (placeholder, change before release)
- [x] `scripts/gen_sprites.py`: pixel maps in code, generates `art/sprites.json`, transparent PNG strips (`Claudenotchi/Sprites/<state>@16|32.png`) and `manifest.json`
- [x] `NotchGeometry` (pure, testable), `NotchPanel` (borderless non-activating, above the menu bar, `constrainFrameRect` override), `NotchWindowController` (picks the notch screen, repositions on screen changes), `PillView` + `SpriteSheet`/`SpriteView` (nearest-neighbor)
- [x] Verified on the built-in notch display: panel at the top edge, 297x32 (notch 185pt plus 56pt of black on each side, symmetric around the notch), mascot crisp and centered in the left extension; the right extension is reserved for status
- [ ] Not done yet: unit tests (target does not exist yet; arrives with Milestone 2), fallback pill on a notchless display not yet seen on a real external screen, no animation yet (static frame 0 of `waiting`)
- Moved this plan into the inner repo (`.claude/plans/`); the old copy in the parent folder is gone.

Phase 2 / Milestone 2 (socket + HookHelper + state machine with unit tests, driven by a fake event script), 2026-10-15:
- [x] `Packages/ClaudenotchiCore` (local Swift package, linked into the app target): `SessionEvent` (hook JSON -> event, newline-delimited wire format), `CompanionState`, `StateMachine` (pure reducer, caller drives `tick(now:)`), `IdleScheduler` (injectable RNG, 30-90s), `EventServer`/`EventClient` (Unix socket at `~/Library/Application Support/Claudenotchi/sock`, mode 0600), `HookRunner` + `claudenotchi-hook` executable (always exits 0, silent)
- [x] 56 unit tests (`swift test` in the package), written test-first; 60 of 60 consecutive full runs green
- [x] Found and fixed a real bug with repeat runs + instrumentation: `stop()` closed the listening descriptor while a late-starting accept thread could still use it, so after the OS reused the descriptor number the stale thread stole the next server's connections (lost events). Fix: accept loop polls the listener plus a wake-up pipe; `stop()` waits for the thread before closing. The regression test is probabilistic (fails mostly under a loaded full-suite run), so keep running the suite repeatedly when touching `EventServer`
- [x] App wiring: `CompanionModel` (server + machine + 500 ms tick) drives `PillView`, which shows frame 0 of the current state's sprite
- [x] `scripts/fake-session.sh` drives the app through every state with the real helper binary. Verified live on the notch display: waiting, thinking, coding, reading, bash, web, needsInput (alert), error, done, and the error (3s) and done (5s) expiries all render the right sprite
- Decisions: sleep and idle rotation only apply from idle states (a long tool run never shows sleeping); needsInput never times out; a failure shows error for at least 3s and ignores softer events meanwhile, but a new prompt or Stop interrupts it
- [ ] Assumption to verify in Milestone 4 with a real session: tool failures arrive as the `PostToolUseFailure` hook event, and `PermissionRequest` exists in the installed Claude Code version
- [ ] Not covered live: idle rotation (30-90s) and sleep (5 min) are only unit tested; the permission flow is one-way for now (blocking Approve/Deny is Milestone 5)
- [ ] Hooks are not registered in `~/.claude/settings.json` yet and the helper is not bundled into the app (Milestone 4)

Phase 2 / Milestone 3 (sprite renderer wired to the exported assets for all states), 2026-10-15:
- [x] `SpriteManifest` (state -> frames, fps, files) and `SpriteAnimation` (frame timing) in the core package; 15 new tests (71 total), including cross-checks that every `CompanionState` has a manifest entry and that each PNG strip's pixel size matches the manifest (verified by deliberately breaking the manifest: the check fails)
- [x] App: `SpriteLibrary` loads clips from the bundle manifest (frames pre-cropped, fps from the manifest), `AnimatedSpriteView` plays them with a `TimelineView` at the state's frame rate, restarting from `stateSince` on every state change; honors Reduce Motion (shows frame 0); `PillView` uses it
- [x] Verified live by burst-capturing the pill while driving states through the real helper: waiting (walk cycle with blink), thinking (dots 1-3), coding (typing), needsInput (alert flash), done (jump + confetti) all animate; about 3% CPU and 16 MB in a Debug build while animating
- [ ] Not exercised live: bash, web, reading, error, videogame, tennis and sleeping animations (assets and manifest are covered by tests; they use the same code path)
- [ ] The 32px art is shipped but not used yet (first used by the expanded view in Milestone 5)
- [ ] Possible later optimization: drop to a lower redraw rate while sleeping; the Figma States-page note that the idle list is "data-driven" is only partly true (idle names live in `manifest.json`, but `IdleScheduler` still has the three activities hard-coded)

Hover-to-expand (user request, 2026-10-15; part of the plan's UI), done:
- [x] Pill expands on hover to the Concept layout (420 x (notch + 64), 32px animated mascot, status title, project folder or the permission message); collapses 0.25s after the mouse leaves. The delay before expanding is user-chosen in the menu bar item ("Expand on hover": Off, Instantly, 0.25, 0.5 (default), 1, 1.5, 2, 3 seconds), stored in `UserDefaults` key `hoverDelay` and applied live
- [x] `HoverIntent` (pure timing), `NotchGeometry` (moved into the core package, now with expanded frame) and `PathDisplay`, all test-first. Every state now has a complete 32px strip (generated by `gen_sprites.py`) so the expanded view animates like the collapsed one
- [x] Verified live by moving the real cursor and polling the window height: 0 s -> 0.05 s, 0.5 s -> 0.54 s, 1.5 s -> 1.55 s, 3 s -> 3.05 s, Off -> never; 30/30 cycles in a soak run
- [x] Fixed on the way: hosting the SwiftUI view directly as the window's content view made SwiftUI resize the panel to its ideal size (420x96) a moment after launch even with `sizingOptions = []`; it now sits inside a plain container view
- [ ] One unexplained stall seen once in an early run (1.5 s and 3 s delays never expanded after an "Instantly" and a 0.5 s hover); not reproducible in 40+ later cycles, so it is not fixed, only noted. If hover ever stops responding, suspect the mouse-tracking path
- [ ] Idle-hover feedback for the expanded pill when `needsInput` fires (auto-expand, Approve/Deny) is Milestone 5

Phase 2 / Milestone 4 (hooks installer and a real Claude Code session end to end), 2026-10-15:
- [x] Verified against Claude Code 2.1.300 with `claude -p --settings <file>` (no change to the real settings): `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure` (fields `error`, `is_interrupt`), `PermissionRequest`, `Stop`, `SessionEnd` all fire. `Notification` did not fire in `-p` mode and stays unverified (interactive only)
- [x] Real traces corrected the state machine (all test-first): after a denied permission prompt there is no `PostToolUse`, only the next `PreToolUse`, so a new tool starting ends `needsInput`; an interrupted tool (`is_interrupt`) is not an error; `SessionEnd` arrives right after `Stop`, so it no longer cuts the done celebration short. Tools can also run in parallel
- [x] `HookInstaller` (core package, 24 tests): merges the 9 hook events into `settings.json` without touching other keys or the user's own hooks; idempotent; timestamped backup beside the file before any change; install then uninstall restores a hook-less file; refuses invalid JSON, files with comments and unexpected `hooks` shapes without writing; writes through symlinks; recognizes its entries by the helper name so uninstall works after the helper moves. Note: it re-serializes the file (keys sorted), so formatting may change; trailing commas are accepted by Foundation and normalized (backup kept)
- [x] `HelperDeployer` (6 tests) copies the embedded helper to `~/Library/Application Support/Claudenotchi/bin/claudenotchi-hook`; hooks point at that stable copy
- [x] Xcode build phase `scripts/embed-helper.sh` builds the helper with SwiftPM and embeds it at `Contents/Helpers/` (user-script sandboxing turned off for this)
- [x] `HookSetup` + menu: installs on launch unless the user uninstalled (opt-out flag `hooksUserOptedOut`), shows status, Install/Uninstall button, error text. Settings path: `-hooksSettingsPath`, else `$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`
- [x] End to end with a real Claude Code session and the real app: thinking -> reading -> error -> needsInput -> done -> waiting; the menu's picker, Install and Uninstall were driven through the real menu (UI scripting) and the opt-out survives a relaunch
- [ ] Hooks were only installed into temp files during testing; the first normal launch of the app will install them into the real `~/.claude/settings.json` (by design, with a backup)
- [ ] Not verified: `Notification` event in interactive sessions; multi-session; the helper is built for the host architecture only (a universal arm64 + x86_64 helper is part of the release milestone); signing of the embedded helper for notarization

Phase 2 / Milestone 5 (attention flow: expand, sound, Approve/Deny, focus terminal), 2026-10-15:
- [x] Decision protocol verified with real Claude Code 2.1.300 (`-p`): a `PermissionRequest` hook that prints `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` lets the tool run; `deny` with a `message` blocks it and Claude sees the message; a hook may block for many seconds (three 8 s answers worked). Payload has `tool_name` and `tool_input` (`command`, `file_path`, `url`), no `tool_use_id`
- [x] `PermissionRequest` is now a blocking, two-way exchange: the helper keeps the socket open and prints the user's decision; `EventServer` holds that connection by request id (`reply(to:with:)`, `cancel(requestID:)`, `cancellations` for a helper that hung up) without blocking other events. With no app, no answer or a hang-up the helper prints nothing, so Claude Code falls back to its own prompt. The installer gives this hook a 600 s timeout (others stay at 10 s)
- [x] `PromptQueue`: prompts shown oldest first; later activity in the same session (`PostToolUse`, `PreToolUse`, `Stop`, ...) means the prompt was resolved elsewhere and its helper is released; the mascot returns to thinking as soon as you answer
- [x] Attention panel (460 x (notch + 118)): alert mascot, "Claude needs your permission", the request (`ToolSummary`: `Bash: <command>`, `Edit: ~/file`, ...), green Approve / red Deny, "N more waiting", "click to focus terminal". Needs-input without a prompt (a `Notification`) shows the message without buttons. VoiceOver: buttons have labels and hints, and "Focus terminal" is an accessibility action. A permission prompt always opens it, regardless of the hover setting
- [x] 8-bit chimes (`scripts/gen_sounds.py` -> `Claudenotchi/Sounds/*.wav`) on entering needs-input and done, plus one for each extra prompt; "Play sounds" toggle in the menu (default on); the WAV files are validated by tests (format, length, level, no clicks)
- [x] Terminal focus: the helper reports its process ancestry and tty; a click brings the nearest regular app in the chain forward (`NSWorkspace.openApplication`), and for Terminal.app / iTerm2 the tab on that tty is selected via AppleScript (usage string added for the Apple Events prompt)
- [x] 213 unit tests (this slice: 73 new); 15/15 consecutive full runs green. Found and fixed a test-harness deadlock (blocking client calls on Swift's cooperative pool); production code was fine
- [x] Verified live with real sessions and the real app: panel opens within about 4 s of the request; real mouse click on **Approve** -> command ran, file created, panel collapsed; **Deny** -> Claude reported "Denied from Claudenotchi", no file; killing the helper (answering in the terminal) -> app logs "the helper hung up"; clicking the panel brought an injected terminal ancestor (Finder) to the front 8 of 8 times
- [ ] Not verified: interactive Claude Code (only `-p` was tested): whether the terminal dialog and the hook run side by side and whether Claude kills the hook when you answer in the terminal; the `Notification` event; tab selection in Terminal.app (script compiles, not run) and iTerm2 (not installed here); Ghostty/VS Code only get the app activated; sound was triggered (log says started) but not heard
- [ ] Unexplained, not reproduced: in the first approve run the prompt was answered about 34 s after it opened by something other than my accessibility click (probably a person at the keyboard); and one early click-to-focus attempt did nothing
- [ ] No keyboard shortcut for Approve/Deny (the panel never becomes the key window)

Milestone 5 visual fix (user report, 2026-10-15): an empty black strip under Approve/Deny, and rounded bottom corners missing in the hover and collapsed states:
- [x] Cause of the corners: the black shape and the three layouts were siblings in one `ZStack`; the attention layout's fixed 460 x 150 inflated the stack, so the shape was bigger than the window and its rounded bottom corners fell outside the visible area (only the attention panel, where size and window matched, was round). The collapsed pill had been square since the hover work for the same reason. Fix: the shape is the `.background` of a `Color.clear` view that takes the window's size, the layouts are `.overlay`s, and everything is clipped to the shape
- [x] Cause of the strip: 118 pt of content height for about 95 pt of content. Now 98 pt (`attentionContentHeight`), and when the request text wraps to a second line the panel grows by one line (`attentionFrame(lines:)`, 4 new tests; line count measured with AppKit in `AttentionLayout`). Long requests keep two lines and end with an ellipsis, so the start of the command stays visible
- [x] Verified by capturing the panel's own window (`screencapture -l <window id>` keeps the alpha) and reading corner alpha: ROUND in collapsed, hover, attention (short and long) and after answering; empty space under the buttons went from about 37 pt to 18 pt, the same for one and two lines. A screenshot of the plain screen could not show this: the background behind the corners was nearly black
- [ ] Not covered by a unit test (SwiftUI layout); re-check the corners with the window-alpha capture after any change to `PillView`

Phase 2 / Milestone 6 (idle scheduler and sleep), 2026-10-15:
- [x] The timing logic (`IdleScheduler` 30-90 s, injectable RNG; `StateMachine` rotation and the 5 minute sleep) came with Milestone 2 and is unit tested; this milestone made the idle list data-driven and verified everything in real time
- [x] `IdleScheduler(activities:)` and `IdleScheduler.activities(fromManifestNames:)`: the `idle` list in `manifest.json` now feeds the scheduler (unknown names and non-idle states are dropped, duplicates collapse, an unusable list gives waiting/videogame/tennis); `CompanionState.isIdleActivity`; 10 new tests (227 in total; 10/10 consecutive runs green). The "data-driven idle list" note on the Figma States page is now true
- [x] Two real-time runs of 335 s with no events and no hovering, logging every state change: first pick 37-71 s after launch, every gap between changes 31-85 s (a pick of the same activity is silent), sleeping at exactly 300.4 s, and a real hook event woke it to thinking. Photographed the pill throughout: waiting (walk cycle), tennis, videogame, sleeping (closed eyes, Z bubbles, breathing) and the wake all render correctly
- [x] CPU in a Debug build: about 3.5 % while idling (6 fps walk cycle redraw), 0.3 % while asleep (2 fps). A Release build will be lower; worth re-measuring in Milestone 8
- [x] Regression caught by the first idle run and fixed: the collapsed mascot was missing (all-black captures). My Milestone 5 layout fix left the three layouts in one stack whose width came from the 460 pt attention layout, which shifted the left-aligned collapsed mascot about 65 pt off screen. Each layout is now its own overlay with its own alignment. Lesson: any check of `PillView` must also assert the mascot is visible, not only the corners (the window-alpha capture plus counting orange pixels does both)
- [ ] Not covered: the Mac itself sleeping and waking (timers jump; the machine should go straight to sleeping, not tested); Reduce Motion in a live run

Bigger collapsed mascot (user request, 2026-10-15): the 16 pt mascot was hard to see in the 32 pt bar.
- [x] Default is now 24 pt (1.5x); "Mascot size" in the menu: Small 16, Medium 24 (default), Large 32; stored in `UserDefaults` key `mascotSize`, applied live. The sizes are 2, 3 and 4 screen pixels per art pixel on a 2x display, so the pixel art stays sharp (28 pt would not). The 32px art is used only at 32 pt or more; smaller sizes scale the 16px art
- [x] The mascot is centered in the 56 pt strip beside the notch. Measured on the real pill over the walk cycle: 16 pt -> 16 x 13 visible, margins 20 left / 10 top / 9 bottom; 24 pt -> 24 x 19.5, 16 / 7 / 5.5; 32 pt -> 32 x 26, 12 / 4 / 2 (tight but never clipped). Picker driven through the real menu
- [ ] The fallback pill on a notchless screen (190 x 32) keeps a fixed 12 pt left padding; check how Large looks there in Milestone 7

Approve does nothing / needs-input comes back without buttons (user report, 2026-10-15):
- [x] Reproduced with real interactive Claude Code 2.1.300 (a pseudo-terminal harness, `claude --permission-mode manual`, stub hooks, then the real app). Findings that corrected my Milestone 5 assumptions: (1) in interactive mode Claude's own dialog and the `PermissionRequest` hook run side by side, and a hook `allow` (even 25 s late) dismisses the dialog ("Allowed by PermissionRequest hook"); (2) the permission `Notification` fires about 6 s after the dialog opens; (3) for `AskUserQuestion` (multiple choice) and `ExitPlanMode` (plan approval) the permission hook fires too, but an `allow` does nothing, the question or plan dialog stays in the terminal; the Notification then re-opens the notch without buttons; (4) pressing Esc on a dialog sends no hook event, Claude Code only kills the waiting hook with SIGTERM
- [x] Fix: `ToolSummary.needsTerminal` (AskUserQuestion, ExitPlanMode) -> `PendingPrompt.canAnswerFromNotch`; for those the panel says "Needs your input" with the question ("Question: ... (+N more)") or "Plan ready for your approval", no Approve/Deny and a shorter panel (`attentionButtonRowHeight`), and the notch never answers. Every permission request keeps its connection open, so a hang-up (Esc) is noticed: with nothing else waiting the state leaves needs-input (`StateMachine.promptCancelled` -> waiting) and the panel closes. This also fixes the same stuck state after Esc on an ordinary permission dialog
- [x] 244 unit tests (10/10 runs green); verified in four real interactive scenarios through the real app: question + Esc, question answered in the terminal, command prompt + Esc, command prompt approved from the notch: the panel closed within 0.3-0.4 s each time and Approve ran the command
- [ ] Headless (`claude -p`) with a question or plan request: the helper now waits for the app's answer that never comes, so the session waits until the hook timeout (600 s) or the next event; interactive use is the target, but a `-p` run that asks a question would stall
- [ ] Other tools whose dialogs need a choice may exist; only these two were found. The interactive harness is in the job tmp folder (not in the repo); it marked the scratch workspace as trusted in `~/.claude.json`

Crab-style idle walk (user request, 2026-10-15): the waiting animation is now a scuttle, not a walk. No claws (the user asked for just the legs): the eyes stay forward, the body slides sideways one pixel at a time (two frames per pixel, legs alternating), then rests on each side for over a second with a leg twitch and a blink (first version moved too fast with only a beat at the edges; slowed on request). 46 frames at 10 fps, a 4.6 s loop (the original walk was 8 frames at 6 fps). Generated by `scripts/gen_sprites.py` (waiting section), including the 32px art. Verified on the live pill: the mascot's centre moves between 25.5 pt and 30 pt, resting about 1.8 s on each side and crossing in about 0.8 s.
- [ ] The travel is small (about 4.5 pt at the default 24 pt size) because the whole motion is drawn inside the 16 px sprite, where the 12 px body leaves 2 px each way. A wider scuttle would need the view to move the sprite (a per-frame travel path in the manifest); not done. The Figma Characters page still shows the previous walk cycle for `waiting`

Phase 2 / Milestone 7 (usage meter, polish, fallback screens, multi-display), 2026-10-15:
- [x] Usage meter: `ModelCatalog` (prices and context windows from the Claude API model table cached 2026-10-06: Fable 5.1 $10/$50, Opus 5.5 $4/$20, Sonnet 5.5 $2/$10, Haiku 5.5 $0.10/$0.50 with a step-up above 100K-token prompts; cache reads per model, cache writes 1.25x/2x input; all current models have a 1M window), `TranscriptUsage` (incremental JSONL reader: one record per content block so a message id counts once and the last record wins, sidechain messages cost money but do not define the context, synthetic messages skipped, partial lines carried over) and `UsageTracker` (reads only the bytes appended since the last refresh). The hover panel shows `context 83% · $34.66` with a small bar (green < 60%, yellow < 85%, red above). Unknown models are never priced: tokens still count and the cost gets a trailing "+". 37 new tests. Checked against an independent Python calculation on this session's real 33 MB transcript: identical (317 messages, 825,806 context tokens, $34.26), read in 0.3 s
- [x] Displays: `ScreenInfo`, `DisplayPreference` (automatic / main / a specific display by UUID) and `DisplayChooser` in the core package with tests; menu "Show on" with the connected displays; an unplugged display falls back to automatic. The notchless fallback pill (190 x 32, top-center, status text beside the mascot) was verified on the real screen with `-forceNotchless YES`: placement, rounded corners, hover (420 x 96) and attention (460 x 130) panels all centered. The pill follows a changed setting live (switches between the notch and fallback layouts without a restart)
- [x] Polish: CPU while idling went from 3.4% to 0.0% of a core (Release build) by playing the sprite animation as a Core Animation keyframe animation on a layer (`LayerSpriteView`) instead of re-rendering SwiftUI ten times a second; identical motion verified (crab 25.5-30 pt, 4 thinking frames, restarts on state change). Removed the now-unused `SpriteAnimation`. "Open at login" toggle (`SMAppService`)
- [x] Single-instance guard: a second copy of the app now quits instead of taking over the hook socket (`EventServer.Failure.alreadyRunning`); `CLAUDENOTCHI_SOCKET` overrides the socket path for the app and the helper (test instances). 8 new tests. 292 tests in total, 10/10 consecutive runs green
- INCIDENT (mine): while testing I ran a second instance next to the user's own Xcode-launched instance and cleaned up with `pkill -x Claudenotchi`, which matches every instance by name. The second instance replaced the hook socket file and left a stale one behind, so the user's running app could no longer receive hooks until restarted. Rules from now on: test instances always use `CLAUDENOTCHI_SOCKET` and are launched with `open -n --env ...`; stop only my own process by PID or by its DerivedData path, never by name; target windows by PID (`winlist` / `winid` take a PID)
- [ ] Not verified: real multi-display (only one display is attached here: the chooser is unit tested and the notchless layout was tried with the override); the "Show on" menu itself (a second instance of the same bundle cannot show a status item while the user's is running); toggling "Open at login" (it would register a scratch build as a login item); the Mac sleeping and waking; Reduce Motion in a live run; fullscreen spaces
- [ ] Hover panel on a notchless screen keeps the 32 pt empty bar at the top (the notch's place); could use that space

Menu bar icon (user request, 2026-10-15): the paw-print SF Symbol is replaced by the mascot as a template image (`MenuBarIcon.imageset`, generated by `scripts/gen_sprites.py` from the first waiting frame: opaque body, eyes cut out, shaded row at 60% alpha; 16 px at 1x, 32 px at 2x and 3x pixel-exact, so it stays sharp). macOS tints it for light, dark, selected and inactive menu bars; the compiled asset is marked `Template Mode: template`.
- Deliberately not the official Claude / Anthropic logo (trademark; see the branding item under Open items). If a licensed logo asset is available it can replace the mascot by dropping a template PNG into the same imageset.
- [ ] Not seen live: a second instance of the same bundle cannot show its status item while the user's own instance is running, so the icon was checked as an asset (alpha of eyes, body and shade rows, compiled template mode, tinted preview), not in the real menu bar. It will appear when the app is relaunched from this build.

Menu bar overlap (user report, 2026-10-15): the 56 pt strips beside the notch cover the last app menus on the left. There is no public API to make macOS flow other apps' menu items around a window (only the hardware notch is reserved; status items of a chosen width reserve space on the right only), so the collapsed pill now keeps the strip as small as the mascot allows:
- [x] Strip width = mascot size + 12 pt, equal on both sides to stay symmetric (`NotchGeometry.collapsedExtension(forMascotSize:)`): 28 / 36 / 44 pt for Small / Medium (default) / Large, instead of a fixed 56 pt. Hover and attention panels are unchanged. Measured live: pill 241 / 257 / 273 pt wide, centered on the notch, mascot inside its strip, and it resizes immediately when "Mascot size" changes. 300 unit tests, 10/10 runs green
- Tried and reverted at the user's request: hanging the pill below the menu bar (it never covers the menu bar, but the user stopped it); not pursued: measuring the free space through the Accessibility API (needs a permission), a strip-width setting, a right-only mascot in a reserved status item
- [ ] The strip still covers up to 36 pt (default) of the left menu bar next to the notch; with very long app menus the last item can still be partly hidden

Milestone 8 (open-source release), 2026-10-15:
- [x] `README.md` (what it is, install, how it works, privacy, menu options, cost estimates, development, non-affiliation notice), `LICENSE` (MIT, copyright holder "Augusto Ildefonso": confirm the name), `docs/states.gif` (every state animated from the real sprite strips and manifest speeds; `scripts/make_preview.py`)
- [x] Universal build: Release builds the helper for arm64 + x86_64 (`scripts/embed-helper.sh`); verified with `lipo` that both the app and the embedded helper are universal
- [x] `scripts/release.sh`: universal Release build -> `dist/Claudenotchi-<version>.dmg` (unsigned by default; `SIGN_IDENTITY` signs the helper and the app with the hardened runtime and a timestamp; `NOTARY_PROFILE` also notarizes and staples). Unsigned and Apple-Development-signed runs verified (signature valid on disk, DMG checksum valid). Bugs found on the way: an identity name with spaces was split by the shell; re-signing with `--force` dropped the entitlements
- [x] Hardened runtime needs `com.apple.security.automation.apple-events` for the terminal-focus AppleScript: added `Claudenotchi/Claudenotchi.entitlements` (wired into both configurations; verified present in the signed app)
- [x] The hardened-runtime universal Release build was launched on a private socket and driven with `scripts/fake-session.sh` through its embedded helper: the permission panel rendered correctly, 0.0 % CPU, about 80 MB resident
- [ ] Cannot be done from here: Developer ID signing and notarization (this Mac has only an "Apple Development" identity; a paid "Developer ID Application" certificate and a `notarytool store-credentials` profile are needed), so the notarize/staple/`spctl` steps of `release.sh` are untested
- [ ] Decisions for the owner before publishing: final bundle id (still the placeholder `dev.claudenotchi.Claudenotchi`) and the `DEVELOPMENT_TEAM`; copyright holder in `LICENSE`; the branding check of the mascot (it resembles Anthropic's Claude Code mascot); the repository name/URL for the README; a Releases page and a Homebrew cask (after the first notarized release); a real screen recording of the notch (the GIF shows the sprites, not the notch)

Hide when Claude is not running (user request, 2026-10-15): the mascot and the notch strip stayed after Claude Code was closed.
- [x] `SessionRegistry` (core): any event registers a session, `SessionEnd` removes it, `prune` drops sessions whose Claude process is gone (closed terminal or crash send no `SessionEnd`); a session with no known process expires after 30 min of silence. `PillVisibility`: visible while a session is open, plus the 5 s "done" celebration and any pending request. The panel fades in and out (`NotchWindowController.applyVisibility`); menu toggle "Hide when Claude isn't running" (default on, key `hideWhenClosed`)
- [x] Finding that corrected my first version: the real Claude Code process is named `2.1.300` (the native binary is `versions/2.1.300`), so matching the process name `claude` never worked. It is recognised by its command line (`KERN_PROCARGS2`, argv[0] `claude`, or `node .../claude` for npm installs). Also a killed process nobody has reaped yet is a zombie and must not count as running
- [x] 327 tests. Verified live on a private instance with real Claude Code: hidden at launch; a real `claude -p` session shows it and it hides after the session and the celebration; a real `claude` killed with `kill -9` (no `SessionEnd`) hides within 5 s; a new session brings it back; with the option off the pill stays. (`winlist` uses `optionAll`, which counts off-screen windows; the on-screen check is `winon`)
- [ ] Not covered: Claude Code already running when the app launches stays unseen until its next hook event (a session that is only sitting at the prompt sends none); the fade animation was not captured frame by frame


"Waiting for input" instead of celebrating (user report, 2026-10-15):
- [x] Cause, reproduced with real Claude Code 2.1.300: about 60 s after `Stop` it sends `Notification` with `notification_type: idle_prompt` ("Claude is waiting for your input"); every Notification was treated as a request, so the mascot left `done`/`waiting` for "needs input" and opened the panel (with the sound) with nothing to answer, until the next event. The payload's `notification_type` was not even read
- [x] Fix: `SessionEvent.notificationType`; in `StateMachine` only `permission_prompt`, `elicitation_dialog` (or an untyped notification from an older Claude) can ask for input, and only while a turn is running (not in done/waiting/idle/sleeping), since the permission notification comes about 6 s after the dialog and can arrive after the work moved on. `idle_prompt` and other types are ignored entirely: they do not cut the celebration short, wake a sleeping mascot or postpone sleep. The real `PermissionRequest` hook is unchanged. 12 new tests (339 total)
- [x] Verified with a private instance: real interactive Claude finished a turn and the panel stayed closed past the 60 s reminder; hand-sent notifications: idle_prompt after Stop / while waiting, and a permission_prompt with no turn running, leave the pill collapsed; a permission_prompt mid-turn opens the panel (positive control) and it closes when the turn finishes
- [ ] Not reproduced: the other path I suspected (a permission notification arriving after an approval made from the notch within about 6 s); the permission dialog never appeared for the harmless command used, so that race is covered only by the unit tests
