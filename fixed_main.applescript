set appPath to POSIX path of (path to me)
-- appPath ends with /, e.g. .../Meeting Prep.app/
-- We want the directory containing the app
set repoPath to do shell script "dirname " & quoted form of (text 1 thru -2 of appPath)
set commandPath to repoPath & "/prep_todays_meetings.sh"

try
	do shell script quoted form of commandPath & " --open"
on error errMsg
	display dialog "Error running Meeting Prep: " & errMsg buttons {"OK"} default button "OK" with icon stop
end try
