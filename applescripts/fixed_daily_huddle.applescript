set appPath to POSIX path of (path to me)
set repoPath to do shell script "dirname " & quoted form of (text 1 thru -2 of appPath)
set commandPath to repoPath & "/RunDailyHuddle.command"

try
	do shell script quoted form of commandPath & " --open"
on error errMsg
	display dialog "Error running Daily Huddle: " & errMsg buttons {"OK"} default button "OK" with icon stop
end try
