# Technical Deep Dive — Focus Music

This document explains the architecture, every major challenge encountered during development, how each was solved, and the reasoning behind key code decisions.

---

## Architecture Overview

The app is an **Automator Application** that runs a shell heredoc containing **AppleScript**. AppleScript orchestrates three things:

1. **Spotify desktop** — via Spotify's native AppleScript dictionary
2. **Chrome tabs** — via Chrome's AppleScript dictionary + `execute javascript`
3. **Chrome window management** — via Chrome AppleScript + `pgrep` process detection

No Accessibility permissions required. Only standard macOS Automation permissions (Spotify + Chrome), granted via dialog on first launch.

```
Automator App
└── Shell Script (osascript heredoc)
    └── AppleScript
        ├── pgrep (detect Chrome --app process)
        ├── Spotify.app (pause via AppleScript)
        ├── Google Chrome
        │   ├── Pass 1: pause all music tabs (JavaScript injected into tabs)
        │   └── Pass 2: find/focus/play app window (JavaScript + window management)
        └── Launch new Chrome --app window if not found
```

---

## Code Walkthrough

### Configuration

```applescript
set playlistID to "list=PL-RUKjstJk9VrU88L7dScinkU95_xZTk6"
set deepLink to "https://music.youtube.com/watch?v=hlWiI4xVXKY&list=PL-RUKjstJk9VrU88L7dScinkU95_xZTk6"
set ytMusicUrl to "music.youtube.com"
set spotifyUrl to "spotify.com"
set appWindowFound to false
```

`playlistID` contains the `list=` parameter used to identify YouTube Music tabs belonging to this playlist. `deepLink` is the full URL opened when launching a fresh app window.

---

### Spotify Desktop Pause

```applescript
if application "Spotify" is running then
  tell application "Spotify"
    if player state is playing then
      pause
    end if
  end tell
end if
```

Spotify exposes a native AppleScript dictionary. `player state` returns `playing`, `paused`, or `stopped`. We check state before pausing to avoid sending a pause command when nothing is playing.

---

### Pass 1 — Pause All Playing Music Tabs

```applescript
set winCount to count of windows
repeat with winIdx from 1 to winCount
  if (count of tabs of window winIdx) > 1 then
    set tabCount to count of tabs of window winIdx
    repeat with tabIdx from 1 to tabCount
      try
        set tabURL to URL of tab tabIdx of window winIdx
        if tabURL contains ytMusicUrl then
          tell tab tabIdx of window winIdx
            execute javascript "var b=document.querySelector('#play-pause-button'); if(b&&b.getAttribute('title')==='Pause')b.click()"
          end tell
        end if
        if tabURL contains spotifyUrl then
          tell tab tabIdx of window winIdx
            execute javascript "var b=document.querySelector('[data-testid=\\'control-button-playpause\\']'); if(b&&b.getAttribute('aria-label')==='Pause')b.click()"
          end tell
        end if
      end try
    end repeat
  end if
end repeat
```

**Why index-based iteration instead of `repeat with t in tabs of w`:**
Loop variable references (`t`, `w`) lose scope inside nested `tell` blocks in AppleScript. `tab tabIdx of window winIdx` always resolves correctly.

**Why skip the app window in Pass 1:**
Two signals are combined to identify the app window reliably:
- `pgrep -qf -- '--app=.*music.youtube.com'` confirms a Chrome `--app` process is currently running
- `count of tabs of window = 1` AND URL contains our `playlistID`

Both must be true. Either alone is unreliable — `pgrep` can match stale or helper processes, and a regular Chrome window can have 1 tab with our URL. Together they correctly identify the app window and skip it, leaving its music untouched for Pass 2 to handle.

**Why no window activation in Pass 1:**
Earlier versions activated each tab before executing JavaScript (bringing it to front). This changed Chrome's window z-order, invalidating the app window's position for Pass 2. JavaScript via `execute javascript` works on background tabs without activation — so we skip it entirely.

**YouTube Music play state detection:**
`#play-pause-button` is a `yt-icon-button` element whose `title` attribute is `"Pause"` when playing and `"Play"` when paused. Reading `.getAttribute('title')` gives exact state. Clicking the element controls playback without toggling.

**Spotify web play state detection:**
Spotify's web player uses `data-testid="control-button-playpause"` on its play/pause button with `aria-label="Pause"` when playing. Same explicit-state approach as YouTube Music.

---

### Pass 2 — Find App Window and Focus/Play It

```applescript
set winCount to count of windows
repeat with winIdx from 1 to winCount
  if (count of tabs of window winIdx) is 1 then
    try
      if URL of active tab of window winIdx contains playlistID then
        set index of window winIdx to 1
        activate
        delay 0.5
        tell tab 1 of window 1
          set btnTitle to execute javascript "document.querySelector('#play-pause-button')?.getAttribute('title')"
        end tell
        if btnTitle is "Play" then
          tell tab 1 of window 1
            execute javascript "document.querySelector('#play-pause-button').click()"
          end tell
        end if
        set appWindowFound to true
        exit repeat
      end if
    end try
  end if
end repeat
```

**Why `count of tabs = 1` identifies the app window:**
Chrome `--app` windows always contain exactly one tab. Regular Chrome windows almost always have multiple tabs. This is a reliable heuristic that requires no OS-level inspection.

This also handles minimized windows — `URL of active tab` works on minimized windows, so the app window is found and unminimized naturally when we call `set index of window winIdx to 1`.

**Why `window 1` after `set index of window winIdx to 1`:**
After `set index of window winIdx to 1`, the target window moves to z-order position 1. All other windows shift. `window winIdx` now points to a **different window** — whatever shifted into that slot. Using `window 1` is always correct after bringing a window to front.

**Why `delay 0.5`:**
Chrome needs a moment to fully render the window after bringing it to front. Without the delay, `execute javascript` runs before the page is ready and `#play-pause-button` returns `missing value`.

**Why only click if `btnTitle is "Play"`:**
`"Play"` means the music is paused — clicking starts it. `"Pause"` means it is already playing — we do nothing. This prevents any toggling behaviour.

---

### Launching a Fresh App Window

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --app='URL' \
  --new-window \
  --autoplay-policy=no-user-gesture-required
```

- `--app=URL` opens Chrome in frameless app mode — no address bar, no tab bar, no bookmarks bar
- `--new-window` forces a new window even if Chrome is already running
- `--autoplay-policy=no-user-gesture-required` bypasses Chrome's autoplay restriction so the playlist starts immediately without a user click

---

## Challenges and Solutions

### Challenge 1 — Distinguishing App Windows from Regular Windows

Chrome's AppleScript exposes no reliable `mode` property. `mode of window` always returns `normal`. Window names via Chrome AppleScript are identical for both types.

**What we tried:**
- `mode of window` → always `normal`
- `name of window` via Chrome AppleScript → `"YouTube Music 🔊"` for both
- System Events window name inspection → app windows show `"YouTube Music"`, regular show `"YouTube Music - Google Chrome"` — this worked but required fragile index correlation between System Events and Chrome

**What worked — final approach (two signals combined, no permissions needed):**

`pgrep -qf -- '--app=.*music.youtube.com'` + Chrome AppleScript window verification.

- `pgrep` alone is unreliable — it can match stale processes, helper processes, or renderer processes that survive after the window is closed (Chrome's multi-process architecture makes 1:1 process-to-window mapping impossible)
- Chrome AppleScript alone is unreliable — a regular 1-tab window can have our playlist URL
- Combined: `pgrep` confirms an `--app` process exists, AppleScript confirms a 1-tab window with our playlist URL exists — together these are a strong enough signal for a personal automation script

**Why not System Events window name inspection:**
System Events can reliably distinguish app windows (name without `"Google Chrome"`) from regular windows. However it requires **Accessibility permission** — one of macOS's most restricted TCC categories. Automator apps have notoriously unreliable TCC behavior: the requesting process is `osascript` or `AutomatorRunner`, not the `.app` itself, making the permission impossible to grant consistently across macOS versions.

---

### Challenge 2 — Explicit Pause/Play Without Toggling

Sending a spacebar keystroke is a toggle — it plays if paused, pauses if playing. We needed explicit control.

**What we tried:**
- `button[aria-label="Pause"]` querySelector → button is inside YouTube Music's shadow DOM, not reachable from document level
- Recursive shadow DOM traversal → YouTube Music uses closed shadow roots (`shadowRoot` returns null)
- `navigator.mediaSession.playbackState` → YouTube Music doesn't set this property
- `document.querySelector('video,audio')` → media elements also in closed shadow DOM
- `audible of tab` Chrome AppleScript property → `Can't make audible of tab N of window M into type specifier` error
- `visibility: visible` on `ytmusic-player-bar` style attribute → worked as a state signal but fragile
- `ytmusic-player-bar` attribute inspection → `player-state` always null

**What worked:**
`yt-icon-button#play-pause-button` has a `title` attribute that reliably reflects state: `"Pause"` when playing, `"Play"` when paused. The element is accessible via `document.querySelector` because YouTube Music uses Polymer's Shady DOM (a light-DOM polyfill), not true closed shadow DOM. Clicking the element controls playback correctly.

---

### Challenge 3 — `execute javascript` Silently Failing

AppleScript's `try` blocks swallow errors silently. We were seeing `22` as output (the script's return value — last evaluated expression from the loop counter) instead of log output, making it impossible to tell why JavaScript wasn't working.

**Root cause:** Chrome had **View → Developer → Allow JavaScript from Apple Events** disabled. This is a per-browser security setting that must be enabled manually. Without it, every `execute javascript` call fails silently.

**Debugging approach:** Used `on error errMsg` instead of bare `try` to surface the actual error message, which revealed the setting immediately.

---

### Challenge 4 — Wrong Window Referenced After `set index`

After `set index of window winIdx to 1`, the window at position `winIdx` moves to position 1. Chrome renumbers all windows. `window winIdx` now points to a completely different window.

This caused JavaScript to execute on the wrong tab, returning `missing value` for `#play-pause-button` — appearing as a DOM access failure when it was actually a window reference error.

**Solution:** After `set index of window winIdx to 1`, always reference the target as `window 1`.

---

### Challenge 5 — Window Z-Order Corruption in Pass 1

Early versions activated tabs during Pass 1 (`set index of window N to 1`, `activate`) to send keyboard shortcuts. This reordered Chrome's windows. App window detection in Pass 2 relied on pre-collected window indices that were now stale — the app window wasn't found, and a new one was launched.

**Solution:** JavaScript via `execute javascript` works on background tabs without any window activation. Removing all activation from Pass 1 keeps window z-order stable throughout the script.

---

### Challenge 6 — AppleScript Quote Escaping in JavaScript Strings

AppleScript strings use double quotes as delimiters. JavaScript attribute selectors also use double quotes (`[aria-label="Pause"]`). Nesting them caused syntax errors.

**What we tried:**
- `\"` escaping → not valid in AppleScript strings
- `quote` constant concatenation (`"before" & quote & "Pause" & quote & "after"`) → works but verbose and error-prone
- `\\` escaping inside the shell heredoc → works but hard to read

**What worked:**
Using `getAttribute('title')` instead of CSS attribute selectors avoids the problem entirely. Single-quoted CSS selectors (`[data-testid=\'control-button-playpause\']`) work when escaped once for the shell heredoc.

---

### Challenge 7 — Loop Variable Scope in Nested Tell Blocks

AppleScript loop variables (`repeat with w in windows`) lose scope inside nested `tell` blocks. Referencing `w` inside `tell application "System Events"` caused `The variable w is not defined` errors.

**Solution:** Index-based iteration throughout. `tab tabIdx of window winIdx` always resolves correctly regardless of nesting depth.

---

### Challenge 8 — `execute javascript` Syntax

`set result to execute javascript "..." of tab` is invalid AppleScript syntax for Chrome. The correct form is:

```applescript
tell tab tabIdx of window winIdx
  set result to execute javascript "..."
end tell
```

Returning values from `execute javascript` works — Chrome's AppleScript bridge preserves JavaScript return types (string, boolean, number). `missing value` is returned when JavaScript returns `null` or `undefined`.

---

### Challenge 9 — Automator TCC and Accessibility Permissions

The script uses `System Events` with `tell process "Google Chrome" to get windows` — which requires Accessibility permission. Granting this proved impossible to do reliably.

**Root cause:** Automator Applications have a broken permission chain. The actual execution hierarchy is:

```
YT Focused Flow.app → Run Shell Script → osascript → System Events
```

macOS evaluates Accessibility permission against `osascript` or `AutomatorRunner` — not the `.app`. This means:
- The `.app` never appears in the Accessibility list
- Adding `osascript` to Accessibility sometimes works, sometimes doesn't
- The grant is not persistent across macOS updates
- Running from Automator directly works; running the `.app` fails

**Solution:** Remove System Events entirely. Replace with `pgrep` + Chrome AppleScript tab count + URL check. This combination requires only standard **Automation permissions** (not Accessibility), which macOS grants via a simple one-time dialog prompt — reliably and persistently.

---

## Key Lessons

- **AppleScript `try` hides everything** — always use `on error errMsg` during debugging
- **Chrome's `execute javascript` needs "Allow JavaScript from Apple Events"** — this is not documented prominently anywhere
- **Window indices shift after `set index`** — always use `window 1` after bringing a window to front
- **Loop variables lose scope in nested tells** — use index-based access throughout
- **Background tab JavaScript works without activation** — avoids all window ordering side effects
- **YouTube Music uses Shady DOM (Polymer polyfill)** — elements are in the regular DOM tree and accessible via `querySelector`, unlike true shadow DOM
- **Automator TCC is broken** — Accessibility permissions granted to the `.app` don't apply at runtime; the permission is evaluated against `osascript` which is unreliable across macOS versions. Avoid System Events for Accessibility-dependent operations in Automator apps
- **Automation permissions vs Accessibility permissions** — Automation (controlling Spotify, Chrome via AppleScript) is granted via a simple one-time dialog. Accessibility (UI scripting via System Events) requires explicit System Settings configuration that Automator apps can't reliably trigger. Design around Automation, avoid Accessibility
- **`pgrep` alone cannot identify a specific window** — Chrome's multi-process architecture means process args don't map 1:1 to windows. Use `pgrep` only as one signal combined with AppleScript verification