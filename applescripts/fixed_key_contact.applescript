set appPath to POSIX path of (path to me)
set repoPath to do shell script "dirname " & quoted form of (text 1 thru -2 of appPath)
set commandPath to repoPath & "/key_contact_prep.sh"

set entry to display dialog "Enter Name or Email for Key Contact Prep:" default answer "" with title "Key Contact Meeting Prep"
set theResult to text returned of entry

try
	do shell script quoted form of commandPath & " " & quoted form of theResult
on error errMsg
	display dialog "Error running Key Contact Prep: " & errMsg buttons {"OK"} default button "OK" with icon stop
end try
