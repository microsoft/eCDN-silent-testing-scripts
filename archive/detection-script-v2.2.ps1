# Intended to be used as a detection script in Intune
# This script checks if a silent runner log file (with the specified Test ID) exists.
#   If it does, it outputs the creation time and time zone of the file, which can be viewed in Intune.
#   If it doesn't, it outputs a message and exits with code 1, which triggers remediation (ie. running the silent runner script).
$TestID = "TEST_ID_HERE"
$logPath = "$env:TEMP\p5_log_" + $TestID + ".txt"

if (Test-Path $logPath) {
  $createdOn = Get-ChildItem $logPath | Select-Object -ExpandProperty CreationTime
  $timeZone = (Get-TimeZone).DisplayName
  Write-Output "$(Get-Date) Log file '$logPath' is present. Created on $createdOn $timeZone. Exiting."
  Exit 0
}
Write-Output "$(Get-Date) No log file detected. Calling for remediation: run silent test $TestId"
Exit 1
