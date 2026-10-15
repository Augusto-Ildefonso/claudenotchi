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

Milestones 4-8: not started.
