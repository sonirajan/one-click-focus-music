# Focus Music — One-Click YouTube Music Focus Session for macOS

A one-click macOS app that instantly drops you into a focused music session. It pauses any music already playing and opens a dedicated YouTube Music playlist in a clean, distraction-free window.

---

## What Kind of App Is This?

This is a **macOS Automator App** — a type of app built with Automator, a tool that comes built into every Mac. Automator lets you automate repetitive tasks by connecting actions together without writing traditional code.

Under the hood, this app runs an AppleScript that:
- Sends commands to Spotify to pause it
- Injects JavaScript into Chrome tabs to pause YouTube Music and Spotify web
- Manages Chrome windows to find, focus, or launch your dedicated music window

You do not need to install anything extra. Automator is already on your Mac.

---

## What It Does

- **Pauses** any music currently playing — YouTube Music tabs, Spotify web, or Spotify desktop app
- **Opens** your focus playlist in a standalone YouTube Music window (no browser chrome, no distractions)
- **Focuses** the existing window if it is already open instead of creating a new one
- **Resumes** playback if the window was open but paused
- **Works** even if the window was minimized to the dock

One click. You are in your focus session.

---

## Prerequisites

- macOS
- Google Chrome
- A YouTube Music account (free or premium)

> The script includes a default publicly available focus music playlist that works out of the box. No configuration needed to get started.

---

## Setup

### Step 1 — Enable JavaScript from Apple Events in Chrome

This allows the script to control Chrome tabs.

1. Open Chrome
2. Go to **View → Developer → Allow JavaScript from Apple Events**
3. Make sure it is checked

> This only needs to be done once.

### Step 2 — Create the Automator App

1. Open **Automator** (search in Spotlight with `⌘ Space`)
2. Click **New Document**
3. Choose **Application**
4. In the search bar, type `Run Shell Script` and drag it into the workflow
5. Paste the script from `focus-music.sh` into the shell script box
6. Go to **File → Save**
7. Name it `Focus Music` and save it to your **Applications** folder

The default playlist is already set in the script and works out of the box. To use your own playlist see **Customization** below.

### Step 3 — Grant Permissions on First Launch

The first time you run the app, macOS will show two permission prompts. Click **Allow** on both:

- **"Focus Music wants access to control Spotify"** — needed to pause Spotify desktop
- **"Focus Music wants access to control Google Chrome"** — needed to control Chrome tabs

These are standard macOS **Automation permissions** (not Accessibility). They are remembered permanently after you allow them once. You can review them anytime under **System Settings → Privacy & Security → Automation**.

### Step 4 — Apply the Custom Icon (Optional)

Run these commands in Terminal from inside the repo folder:

```bash
cp icon.icns "/Applications/Focus Music.app/Contents/Resources/AutomatorApplet.icns"
cp icon.icns "/Applications/Focus Music.app/Contents/Resources/ApplicationStub.icns"

sudo rm -rf /Library/Caches/com.apple.iconservices.store
killall Dock
```

If the icon still shows as Automator after this, log out and back in.

> `icon.icns` is already included in the repo — no conversion needed.

### Step 5 — Add to Dock or Desktop

- Drag `Focus Music.app` from Applications to your **Dock**
- Or drag it to your **Desktop** to keep it visible

### Step 6 — Set a Keyboard Shortcut (Optional)

1. Go to **System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts**
2. Click `+`
3. Set **Application** to `All Applications`
4. Set **Menu Title** to `Focus Music`
5. Assign your shortcut (e.g. `⌃⌥⌘M`)

---

## Customization (Optional)

The script works out of the box with the included public focus music playlist. To use your own:

1. Open YouTube Music in Chrome and navigate to your playlist
2. Copy the full URL from the address bar
3. In `focus-music.sh`, replace these two lines:

```applescript
set playlistID to "list=YOUR_PLAYLIST_ID"
set deepLink to "YOUR_FULL_PLAYLIST_URL"
```

| What to change | Where in the script |
|---|---|
| Your playlist | `set playlistID` and `set deepLink` |
| Spotify web support | Already included — works automatically |
| Spotify desktop support | Already included — works automatically |

---

## What Gets Paused

When you launch the app, it automatically pauses:

- Any **YouTube Music** tab playing in Chrome
- Any **Spotify web** tab playing in Chrome
- The **Spotify desktop app** if it is running and playing

---

## Requirements

- macOS 12 or later (Monterey+)
- Google Chrome (any recent version)
- Automator (built into macOS)