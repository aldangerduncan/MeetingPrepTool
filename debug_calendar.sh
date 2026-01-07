#!/bin/bash
# Checks available calendars and lists them.
# Helps debug if the Google Account is synced and visible.

osascript -e '
tell application "Calendar"
    set calendarNames to name of every calendar
    set allCalInfo to ""
    
    repeat with calName in calendarNames
        set allCalInfo to allCalInfo & "- " & calName & return
    end repeat
    
    return "Available Calendars:\n" & allCalInfo
end tell
'
