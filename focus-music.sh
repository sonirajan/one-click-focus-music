osascript << 'EOF'

-- Configuration
set playlistID to "list=PL-RUKjstJk9VrU88L7dScinkU95_xZTk6"
set deepLink to "https://music.youtube.com/watch?v=hlWiI4xVXKY&list=PL-RUKjstJk9VrU88L7dScinkU95_xZTk6"
set ytMusicUrl to "music.youtube.com"
set spotifyUrl to "spotify.com"
set appWindowFound to false

-- Check if a Chrome --app process for YouTube Music is currently running
-- Combined with AppleScript window check gives reliable app window detection
set appProcessRunning to false
try
  do shell script "pgrep -qf -- '--app=.*music.youtube.com'"
  set appProcessRunning to true
on error
  set appProcessRunning to false
end try

-- Pause Spotify desktop app if running and playing
if application "Spotify" is running then
  tell application "Spotify"
    if player state is playing then
      pause
    end if
  end tell
end if

if application "Google Chrome" is running then
  tell application "Google Chrome"

    -- Pass 1: pause music in all windows except our app window
    -- app window = pgrep confirms process running + 1 tab + our playlist URL
    -- both signals required — either alone is unreliable
    set winCount to count of windows
    repeat with winIdx from 1 to winCount
      set isAppWindow to false
      if appProcessRunning and (count of tabs of window winIdx) is 1 then
        try
          if URL of active tab of window winIdx contains playlistID then
            set isAppWindow to true
          end if
        end try
      end if

      if not isAppWindow then
        set tabCount to count of tabs of window winIdx
        repeat with tabIdx from 1 to tabCount
          try
            set tabURL to URL of tab tabIdx of window winIdx

            -- pause YouTube Music tab if playing
            if tabURL contains ytMusicUrl then
              tell tab tabIdx of window winIdx
                execute javascript "var b=document.querySelector('#play-pause-button'); if(b&&b.getAttribute('title')==='Pause')b.click()"
              end tell
            end if

            -- pause Spotify web tab if playing
            if tabURL contains spotifyUrl then
              tell tab tabIdx of window winIdx
                execute javascript "var b=document.querySelector('[data-testid=\\'control-button-playpause\\']'); if(b&&b.getAttribute('aria-label')==='Pause')b.click()"
              end tell
            end if

          end try
        end repeat
      end if
    end repeat

    -- Pass 2: find app window — 1 tab + our playlist URL
    -- pgrep not used here: we want to focus whatever window has our URL
    set winCount to count of windows
    repeat with winIdx from 1 to winCount
      if (count of tabs of window winIdx) is 1 then
        try
          if URL of active tab of window winIdx contains playlistID then
            set index of window winIdx to 1
            activate
            delay 0.5

            -- window is now at index 1 after set index — use window 1
            tell tab 1 of window 1
              set btnTitle to execute javascript "document.querySelector('#play-pause-button')?.getAttribute('title')"
            end tell

            if btnTitle is "Play" then
              tell tab 1 of window 1
                execute javascript "document.querySelector('#play-pause-button').click()"
              end tell
            end if
            -- if "Pause": already playing, do nothing

            set appWindowFound to true
            exit repeat
          end if
        end try
      end if
    end repeat

  end tell
end if

-- No app window found: launch a fresh one with autoplay
if not appWindowFound then
  do shell script "/Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --app='" & deepLink & "' --new-window --autoplay-policy=no-user-gesture-required > /dev/null 2>&1 &"
end if

EOF