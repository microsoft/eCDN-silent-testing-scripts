# Intune Detection Script for Silent Test Runner Log Monitoring
# 
# This script monitors the TEMP directory for silent test runner log files matching a time-based pattern.
# It searches for log files with the pattern "p5_script_runner_YYYYMMDD_HH*.txt" from the current hour.
# 
# Behavior:
#   - If matching log files are found: Outputs detailed information including creation time, timezone, 
#     and complete log content for each file, then exits with code 0 (success/compliant)
#   - If no matching log files are found: Outputs a remediation request message, the content of the latest log file, and exits with 
#     code 1 (non-compliant), triggering Intune remediation to run the silent test runner script
#
# Note: The file name pattern includes a wildcard (*) to match any TestID suffix after the 
# timestamp. If the remediation script uses a static TestID, the wildcard is unnecessary in that context.
#
# Important: To avoid instancing multiple concurrent runners, pay special attention to the relationship between...
# - the TestIdPattern in this script
# - the ScenarioDuration in the silent-tester-runner-windows.ps1 script
# - and the frequency of the Intune remediation schedule.
#
# One useful configuration for each is as follows:
# - TestIdPattern: "runner_$(Get-Date -Format "yyyyMMdd")*"
# - Silent runner script's ScenarioDuration: 82800 seconds (23 hours)
# - Intune remediation schedule: Every 1 hour
# This combination will ensure that a runner is created each day, and the Intune remediation will check every hour for the day's log file - indicating that a runner is active.
#
# Note: Only the last line of output from this script will be displayed in the Intune console.
$BasePattern = "p5_script_"
$TestIdPattern = "runner_$(Get-Date -Format "yyyyMMdd_HH")*"
$FullLogFilenamePattern = $BasePattern + $TestIdPattern + ".txt"
if ($logs = (Get-ChildItem -Path $env:TEMP -Filter $FullLogFilenamePattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
  $timeZone = (Get-TimeZone).DisplayName
  Write-Output "$(Get-Date) Log file(s) detected:"
  $logs | ForEach-Object {
    $logContent = try { (Get-Content -Path $_.FullName -ErrorAction Stop) -join "`  | " -replace '\s{2,}', '  ' } catch { "Error reading log file: $_" }
    Write-Output "$(Get-Date) Runner ran. Log file '$($_.Name)' is present. Created on $($_.CreationTime) $timeZone.  | LOG CONTENT >|  $logContent"
  }
  Exit 0
}
$latestLogContent = try {(
    Get-ChildItem -Path $env:TEMP -Filter "$BasePattern*.txt" -ErrorAction Stop | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 | 
    ForEach-Object { 
      (Get-Content -Path $_.FullName -ErrorAction Stop) -join "`  | " -replace '\s{2,}', '  ' 
    }
)} catch { 
  "Error reading latest log file: $_" 
}
$priorLogContent = if ($latestLogContent) { 
  "PRIOR RUN LOG CONTENT >|  $latestLogContent"
} else { 
  "No prior log files found." 
}
Write-Output "$(Get-Date) No log file detected with pattern `"$TestIdPattern`". Calling for remediation.  | $priorLogContent"
Exit 1
