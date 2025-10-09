# Intune Detection Script for Silent Test Runner Log Monitoring
# 
# This script monitors the TEMP directory for silent test runner log files matching a time-based pattern.
# It searches for log files with the pattern "p5_script_runner_YYYYMMDD_HH*.txt" from the current hour.
# 
# Behavior:
#   - If matching log files are found: Outputs detailed information including creation time, timezone, 
#     and complete log content for each file, then exits with code 0 (success/compliant)
#   - If no matching log files are found: Outputs a remediation request message and exits with 
#     code 1 (non-compliant), triggering Intune remediation to run the silent test runner
#
# Note: The file name pattern includes a wildcard (*) to match any TestID suffix after the 
# timestamp. If the remediation script uses a static TestID, the wildcard is unnecessary in that context.
#
# Important: To avoid instancing multiple concurrent runners, pay special attention to the relationship between...
# - the TestIdPattern in this script
# - the ScenarioDuration in the silent-tester-runner-windows.ps1 script
# - and the frequency of the Intune remediation schedule.
#
# One common configuration for each is as follows:
# - TestIdPattern: "runner_$(Get-Date -Format "yyyyMMdd")*"
# - ScenarioDuration: 86400 seconds (24 hours)
# - Intune remediation schedule: Every 1 hour
# This combination will ensure that a 24-hour runner is created each day, and the Intune remediation will check every hour for the day's log file - indicating that a runner is active.
#
# Note: Only the last line of output from this script will be displayed in the Intune console.
$TestIdPattern = "runner_$(Get-Date -Format "yyyyMMdd_HH")*"
$logPattern = "p5_script_$TestIdPattern.txt"
if ($logs = (Get-ChildItem -Path $env:TEMP -Filter $logPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
  $timeZone = (Get-TimeZone).DisplayName
  Write-Output "$(Get-Date) Log file(s) detected:"
  $logs | ForEach-Object {
    $logContent = try { (Get-Content -Path $_.FullName -ErrorAction Stop) -join "`  | " -replace '\s{2,}', '  ' } catch { "Error reading log file: $_" }
    Write-Output "$(Get-Date) Log file '$($_.Name)' is present. Created on $($_.CreationTime) $timeZone.  | LOG CONTENT:  $logContent"
  }
  Exit 0
}
Write-Output "$(Get-Date) No log file detected with pattern `"$TestIdPattern`". Calling for remediation."
Exit 1
