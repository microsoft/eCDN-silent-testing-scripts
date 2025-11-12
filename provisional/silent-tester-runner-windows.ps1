[CmdletBinding()]
param (
  [string] $TenantID = "TENANT_ID", # IMPORTANT! Either replace 'TENANT_ID' with your actual Microsoft Tenant Id or pass it as an argument.
  [string] $TestID = "runner_$(Get-Date -Format "yyyyMMdd_HHmmss")", # Must be unique per instance unless using AllowMultipleRuns. Dynamic timestamp avoids need to manually update static TestID values for repeated runs.
  [Alias ("Seconds")]
  [int] $ScenarioDuration = 86400, # Default is 86400 seconds, or 24 hours.
  [Alias ("SCCM","Intune")]
  [switch] $UEM_Compatible_Mode, # Use for better compatibility with UEM solutions such as SCCM and Intune. Hard-code to =$true for use with Intune.
  [Alias ("Force")]
  [switch] $AllowMultipleRuns, # Use if you want to be able to run more the once with the same $TestID on the machine. 2 tabs might jump to user.
  [Alias ("Chrome")]
  [switch] $PreferChrome,
  [string] $CustomChromiumPath = "", # Use if you want to specify the path to the Chromium executable.
  [Alias ("ShowRunner","DontHideRunner")]
  [switch] $DirectRunner, # Use if you want to run the Chromium process in a visible window. This is useful for debugging purposes.
  [string] $AdapterId, # Ensure the string is URL encoded, as it will be used in the URL. Default is PowerShell, or Direct if -DirectRunner switch is used. For troubleshooting, can use this dynamic, default value ="$(hostname)-$(Get-Date -Format "HHmm")"
  [Alias ("ReturnRunner")]
  [switch] $PassThru, # Returns the process object of the Chromium process.
  [ValidateSet("General", "GCC", "GCCH")]
  [Alias ("Env")]
  [string] $Environment = "General", # Specify the environment: General, GCC, or GCCH.
  [switch] $OldHideMethod # Use if you want to use the old method of hiding the Chromium window using a C# class. This is not compatible with the --headless flag.
)
#############
### SETUP ###
#############

### Setting up the variables and function ###
$ScriptVersion = "2.3.8.4"
$durationMinimum = 10
$HeadlessRunner = -not $DirectRunner -and -not $OldHideMethod
$logPath = "$env:TEMP\p5_log_" + $TestID + ".txt"
$errLogPath = "$env:TEMP\p5_err_" + $TestID + ".txt"
$p5UserDataDir = "$env:TEMP\p5-user-" + $TestID
$scriptLogPath = "$env:TEMP\p5_script_" + $TestID + ".txt"
$preferencesFilePath = $p5UserDataDir + "\Default\Preferences"
$cacheFolderPath = $p5UserDataDir + "\Default\Cache"
if (!$AdapterId) { $AdapterId = if ($DirectRunner) { 'Direct' } else { 'PowerShell' } }
$baseURL = switch ($Environment) {
  "GCC"  { "https://st-sdk.ecdn.gcc.teams.microsoft.com" }
  "GCCH" { "https://st-sdk.ecdn.gov.teams.microsoft.us" }
  default { "https://st-sdk.ecdn.teams.microsoft.com" }
}
$pageURL = "$baseURL/?customerId=${TenantID}&adapterId=$AdapterId"
$defaultPaths = @(
  "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
  "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
  "C:\Program Files\Google\Chrome\Application\chrome.exe")

# Function to write output to the console or host, and log it to a file
function Out-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Object,
        [ConsoleColor]$ForegroundColor = 'White'
    )
    # Output message to console or host depending on UEM mode and message type
    $firstWord = ($Object -split '\s+')[0].TrimEnd(':')
    if ($firstWord -eq 'ERROR') {
      Write-Error   ($Object = "$(Get-Date)  $Object")
    }
    elseif ($UEM_Compatible_Mode) {
        Write-Output $Object
    } else {
      # Not UEM mode or Error message
      if ($firstWord -eq 'WARNING') {
        Write-Warning ($Object = "$(Get-Date)  $Object")
      }
      else {
        Write-Host $Object -ForegroundColor $ForegroundColor
        }
    }
    # Attempt to log the output to the script log file, retrying up to 3 times on failure
    for ($i = 0; $i -lt 3; $i++) {
        try { Add-Content -Path $scriptLogPath -Value $Object -Encoding UTF8 -ErrorAction Stop; break }
        catch { 
          if ($i -eq 2) { Write-Output "Failed to write to log file '$scriptLogPath' after 3 attempts. Error: $_" } 
          else {
            Write-Verbose "Retrying to write to log file (attempt $($i + 2) of 3)..."
            Start-Sleep -Milliseconds 300 
          }
        }
    }
}

### Parameter validation ###
if ($TestID -notmatch '^[a-zA-Z0-9_\-]+$') {
  Write-Error "Invalid Parameter: Test ID. Please provide a valid Test ID containing only alphanumeric characters, underscores, or hyphens."
  Exit 1
}
$RegexForTenantId = '^[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}$'
if ($TenantID -notmatch $RegexForTenantId) {
  Out-Log "ERROR: Invalid Parameter: Tenant ID '$TenantID'. Please provide a valid Tenant ID."
  Exit 1
}
if ($ScenarioDuration -lt $durationMinimum) {
  Out-Log "ERROR: Invalid Parameter: Scenario Duration '$ScenarioDuration'. Please provide a Scenario Duration of greater than $durationMinimum seconds."
  Exit 1
}
if ($CustomChromiumPath -and !(Test-Path $CustomChromiumPath)) {
  Out-Log "ERROR: Invalid Parameter: Custom Chromium Path '$CustomChromiumPath'. Please provide a valid path to the Chromium executable."
  Exit 1
}

### Checking if the script is already running on this machine with the same TestID ###
if ((Test-Path $logPath) -and (!$AllowMultipleRuns)) {
  Out-Log "ERROR: Test '$TestID' already ran on this machine. aborting"
  Exit 2
}

# Function to check browser-specific policies
function Test-BrowserPolicies {
    param(
        [string]$BrowserPath,
        [bool]$IsHeadless
    )
    
    $isEdge = $BrowserPath -match "msedge\.exe"
    $isChrome = $BrowserPath -match "chrome\.exe"
    
    if ($isEdge) {
$edgePoliciesPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        
# Check for Edge BrowserSignin policy that may block the runner
$edgePolicy = Get-ItemProperty -Path $edgePoliciesPath -Name BrowserSignin -ErrorAction SilentlyContinue
if ($null -ne $edgePolicy -and $edgePolicy.BrowserSignin -eq 2) {
            Out-Log "WARNING: Edge policy 'BrowserSignin' is set to 2 (ForceSignIn). The headless runner is likely to be blocked by this policy as it requires browser sign-in. You can use the -DirectRunner switch to verify this. If so, remove or change the 'BrowserSignin' policy. Using Chrome via the -PreferChrome switch may be a usable workaround." -ForegroundColor Yellow
}

# Check for Edge WebRtcLocalhostIpHandling policy that may hide local IPs
$localIPsPolicy = Get-ItemProperty -Path $edgePoliciesPath -Name WebRtcLocalhostIpHandling -ErrorAction SilentlyContinue
if ($localIPsPolicy.WebRtcLocalhostIpHandling -in @("default_public_interface_only", "disable_non_proxied_udp")) {
            Out-Log "WARNING: Local IPs may be inaccessible due to Edge policy 'WebRtcLocalhostIpHandling'. The runner may not function correctly. You can check the registry path '$edgePoliciesPath' to verify this. Remove or change the 'WebRtcLocalhostIpHandling' policy to 'default' or 'default_public_and_private_interfaces' to enable local IP access." -ForegroundColor Yellow
            # Alternatively, you can use the WebRtcIPHandlingUrl policy to allow local IPs access for specific URLs. 
            # For specific guidance, see https://learn.microsoft.com/ecdn/troubleshooting/troubleshoot-ecdn-performance-issues#webrtc-ip-handling-policy-blocking-peering
}

# Check for Edge HeadlessModeEnabled policy which is known to block silent runners
$edgeHeadlessPolicy = Get-ItemProperty -Path $edgePoliciesPath -Name HeadlessModeEnabled -ErrorAction SilentlyContinue
        if ($IsHeadless -and $null -ne $edgeHeadlessPolicy -and $edgeHeadlessPolicy.HeadlessModeEnabled -eq 0) {
            Out-Log "WARNING: Edge policy 'HeadlessModeEnabled' is set to 0 (Disabled). The silent (ie. headless) runner will be blocked by this policy and the process is expected to close immediately. You can check the registry path '$edgePoliciesPath' to verify this. Remove or change the 'HeadlessModeEnabled' policy to '1' to enable headless mode." -ForegroundColor Red
        }
    }
    elseif ($isChrome) {
        $chromePoliciesPath = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
        
        # Check for Chrome BrowserSignin policy (equivalent to Edge's BrowserSignin)
        $chromeBrowserSigninPolicy = Get-ItemProperty -Path $chromePoliciesPath -Name BrowserSignin -ErrorAction SilentlyContinue
        if ($null -ne $chromeBrowserSigninPolicy -and $chromeBrowserSigninPolicy.BrowserSignin -eq 2) {
            Out-Log "WARNING: Chrome policy 'BrowserSignin' is set to 2 (Forced). The headless runner is likely to be blocked by this policy as it requires browser sign-in. You can use the -DirectRunner switch to verify this. If so, remove or change the 'BrowserSignin' policy." -ForegroundColor Yellow
        }

        # Check for Chrome WebRtcIPHandling policy that may hide local IPs (equivalent to Edge's WebRtcLocalhostIpHandling)
        $chromeWebRtcIPHandling = Get-ItemProperty -Path $chromePoliciesPath -Name WebRtcIPHandling -ErrorAction SilentlyContinue
        if ($null -ne $chromeWebRtcIPHandling -and $chromeWebRtcIPHandling.WebRtcIPHandling -in @("default_public_interface_only", "disable_non_proxied_udp")) {
            Out-Log "WARNING: Local IPs may be inaccessible due to Chrome policy 'WebRtcIPHandling'. The runner may not function correctly. You can check the registry path '$chromePoliciesPath' to verify this. Remove or change the 'WebRtcIPHandling' policy to 'default' or 'default_public_and_private_interfaces' to enable local IP access." -ForegroundColor Yellow
            # Alternatively, you can use the WebRtcIPHandlingUrl policy to allow local IPs access for specific URLs.
            # For specific guidance, see https://learn.microsoft.com/ecdn/troubleshooting/troubleshoot-ecdn-performance-issues#webrtc-ip-handling-policy-blocking-peering
        }

        # Note: Chrome doesn't have a direct equivalent to Edge's HeadlessModeEnabled policy
    }
    else {
        Out-Log "INFO: Using custom Chromium executable. Browser-specific policy checks skipped." -ForegroundColor Gray
    }
}

### Old method: C# class to hide/show the browser window ###
$definition = @"
  [DllImport("user32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public static void Hide(IntPtr hWnd) {
    if ((int)hWnd > 0)
      ShowWindow(hWnd, 0);
  }
  public static void SetWindow(IntPtr hWnd, int nCmdShow) {
    if ((int)hWnd > 0) {
      Console.WriteLine("{0}  Executing ShowWindow({1}, {2})", DateTime.Now, hWnd, nCmdShow);
      ShowWindow(hWnd, nCmdShow);
    }
  }
"@
if (-not $HeadlessRunner -and -not ("my.WinApi" -as [type])) {
  Add-Type -MemberDefinition $definition -Namespace my -Name WinApi
}

###################
### MAIN SCRIPT ###
###################
Out-Log "Script version: $ScriptVersion"
Out-Log "Test ID: $TestID"
Out-Log "Adapter ID: $AdapterId"

### Selecting the Chromium executable path ###
if (!$CustomChromiumPath -or !(Test-Path $CustomChromiumPath)) {
  try {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe') {
      $edgeExe = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' "(default)"
      $defaultPaths = ,$edgeExe + $defaultPaths
      Write-Verbose "Found Edge executable at $edgeExe"
    }
  }
  catch {
    # do nothing
  }
  
  if ($PreferChrome) {
    $defaultPaths = $defaultPaths | Sort-Object { $_ -match "chrome" } -Descending
  }

  for($i = 0; $i -le $defaultPaths.Count; $i++ ) {
    $BrowserPath = $defaultPaths[$i]
    Write-Verbose "Checking for $BrowserPath"
    
    if ($BrowserPath -and (Test-Path $BrowserPath)) {
      $CustomChromiumPath = $BrowserPath
      break
    }
    Write-Verbose "Not found"
  }

  if (!$CustomChromiumPath) {
    Out-Log "ERROR: Could not find Edge or Chrome executable. Please set the `$CustomChromiumPath variable in the script to your Chromium browser's executable path."
    Exit 4
  }

  if ($PreferChrome -and $CustomChromiumPath -notmatch "chrome\.exe") {
    Out-Log "Chrome not found" -ForegroundColor DarkGray
  }
}
Out-Log "Using Chromium at path '$CustomChromiumPath'"

### Check browser-specific policies ###
Test-BrowserPolicies -BrowserPath $CustomChromiumPath -IsHeadless $HeadlessRunner

### Starting the browser process ###
$browserArguments = @(
  "$($pageURL)",
  "--use-fake-ui-for-media-stream",
  "--no-default-browser-check",
  "--disable-first-run-ui"
  "--hide-crash-restore-bubble",
  "--autoplay-policy=no-user-gesture-required",
  "--disable-backgrounding-occluded-windows",
  "--disable-background-media-suspend",
  "--disable-renderer-backgrounding",
  "--disable-gpu",
  "--remote-debugging-port=0",
  "--disable-infobars",
  "--disable-restore-session-state",
  "--user-data-dir=$p5UserDataDir",
  "--disable-gesture-requirement-for-media-playback",
  "--disable-background-networking",
  "--disable-background-timer-throttling",
  "--disable-breakpad",
  "--disable-client-side-phishing-detection",
  "--disable-default-apps",
  "--disable-dev-shm-usage",
  "--disable-extensions",
  "--disable-field-trial-config",
  "--disable-features=site-per-process,WebRtcHideLocalIpsWithMdns",
  "--disable-hang-monitor",
  "--disable-popup-blocking",
  "--disable-prompt-on-repost",
  "--disable-sync",
  "--disable-translate",
  "--metrics-recording-only",
  "--no-first-run",
  "--safebrowsing-disable-auto-update",
  "--enable-automation",
  "--password-store=basic",
  "--use-mock-keychain",
  "--mute-audio",
  "--process-per-site"
)
if ($HeadlessRunner) {
  $browserArguments += "--headless=new"
}

$Process = Start-Process $CustomChromiumPath -RedirectStandardOutput $logPath -RedirectStandardError $errLogPath -PassThru -ArgumentList ($browserArguments -join ' ') -WorkingDirectory $env:TEMP
Out-Log "$(($startedAt=Get-Date))  Started Chromium $($Process.Name) process, with id: $($Process.id)"
# Swapping old window hide method with the --headless flag, as it doesn't work with the headless flag and will just indefinitely loop while it waits for the window to get a WindowHandle assigned.  Which it won't since it's headless.
if ($OldHideMethod -and -not $DirectRunner -and [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {
  While ($Process.MainWindowHandle -eq 0 -and ($elapsed=(Get-Date) - $startedAt).TotalSeconds -lt 3) { Start-Sleep -m 100 }
  [my.WinApi]::Hide($Process.MainWindowHandle)
  Write-Host "Window hidden after $elapsed" -F DarkGray
}

### Setting up the watchdog process ###
$chromePid = $Process.id

# PowerShell-native Watchdog process
$extraTimeout = $ScenarioDuration + ($timeoutBonus = 10)
$watchdogScript = @"
Write-Host (\"`n\"*7)
function Log-WatchdogMessage {
  param([string]`$Message)
  `$line = \"`$(Get-Date)  [Watchdog] `$Message\"
  Write-Host `$line
  Add-Content -Path '$scriptLogPath' -Value `$line -Encoding UTF8
}

Log-WatchdogMessage \"Started. Monitoring chromium process with PID: $chromePid for $extraTimeout seconds\"

`$startTime = Get-Date
`$endTime = `$startTime.AddSeconds($extraTimeout)

while ((`$now = Get-Date) -lt `$endTime) {
  `$totalSeconds = [math]::Round((`$endTime - `$startTime).TotalSeconds)
  `$elapsedSeconds = [math]::Round((`$now - `$startTime).TotalSeconds)
  `$percentCompleted = if (`$totalSeconds -gt 0) { [math]::Min([math]::Round((`$elapsedSeconds / `$totalSeconds) * 100), 100) } else { 100 }
  Write-Progress -Activity \"Watchdog Monitoring\" -Status \"Elapsed: `$elapsedSeconds sec / `$totalSeconds sec\" -PercentComplete `$percentCompleted
  Start-Sleep -Seconds 1

  if (-not (Get-Process -Id $chromePid -ErrorAction SilentlyContinue)) {
  `$secondsEarly = [math]::Round((`$endTime - `$now).TotalSeconds) - $timeoutBonus
  `$endingNuance = if (`$elapsedSeconds -lt $durationMinimum) { \"not found\" } else { \"no longer running\" }
  Log-WatchdogMessage \"Process $chromePid `$endingNuance. Appears to have been ended prematurely (`$secondsEarly seconds early)\"
    `$endedPrematurely = `$true
    break
  }
  else {
    # Write-Host \"Process $chromePid is still running.\"
  }
}

# Final check and attempt to stop if still running
try {
  `$proc = Get-Process -Id $chromePid -ErrorAction Stop
  Log-WatchdogMessage \"Expiration time reached. Attempting to stop chromium process\"
  try {
    Stop-Process -Id $chromePid -Force -ErrorAction Stop
    Log-WatchdogMessage \"Stopped chromium process\"
  } catch {
    Log-WatchdogMessage \"Failed to stop chromium process with error: `$_\"
  }
} catch {
  if (!`$endedPrematurely) {
    Log-WatchdogMessage \"Chromium process already exited at end\"
  }
}

# Always remove cache folder
try {
  Remove-Item -Path '$cacheFolderPath' -Recurse -Force -ErrorAction Stop
  Log-WatchdogMessage \"Cleaned up cache folder '$cacheFolderPath'\"
} catch {
  # do nothing
}

Log-WatchdogMessage \"Exiting\"
Start-Sleep -Seconds 5
"@

$watchdogProcess = Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile", "-Command", $watchdogScript -PassThru
Write-Verbose "            Started PowerShell Watchdog process, with id: $($watchdogProcess.id)"

if ($PassThru) {
  # Initialize the global list if it doesn't already exist
  if (-not $Global:eCDNRunners) {
    Write-Verbose "Initializing global eCDNRunners list"
    $Global:eCDNRunners = @()
  }

  $preCount = $Global:eCDNRunners.Count

  # Remove any processes in the eCDNRunners list that are no longer running.
  $Global:eCDNRunners = @($Global:eCDNRunners | Where-Object { 
    try {
      if ($_.HasExited -eq $false) {
        Write-Verbose "Runner with ID $($_.Id) is still running"
        $true
      } else {
        Write-Verbose "Removing runner with ID $($_.Id) which has exited"
        $false
      }
    } catch {
      Write-Verbose "Removing runner with ID $($_.Id) from global eCDNRunners list"
      $false
    }
  })

  # Re-initialize the global eCDNRunners list if it doesn't already exist.
  if (-not $Global:eCDNRunners) { $Global:eCDNRunners = @() }

  if (($postCount = $Global:eCDNRunners.Count) -ne $preCount) {
    Write-Verbose "Removed $($preCount - $postCount) processes from the global eCDNRunners list"
  }
  # Add properties to the runner process object
  $Process | Add-Member -MemberType NoteProperty -Name "TestID" -Value $TestID
  $Process | Add-Member -MemberType NoteProperty -Name "TenantID" -Value $TenantID
  $Process | Add-Member -MemberType NoteProperty -Name "ScenarioDuration" -Value $ScenarioDuration
  $Process | Add-Member -MemberType NoteProperty -Name "isHeadless" -Value $HeadlessRunner
  # Adding methods to control the visibility of the Chromium window
  $Process | Add-Member -MemberType ScriptMethod -Name SetRunnerWindow -Value {
    param($nCmdShow=1) # Default to SW_SHOWNORMAL
    if ($this.isHeadless) {
      Write-Host "Headless mode is enabled. Cannot set window visibility." -F DarkGray
      return
    }
    # ensure $nCmdShow is an int between 0 and 11
    if ($nCmdShow -lt 0 -or $nCmdShow -gt 11 -or $nCmdShow -notmatch '^\d+$') {
      Write-Host "Invalid nCmdShow value [$($nCmdShow.GetType())]'$nCmdShow'. Must be between 0 and 11." -F Red
      return
    }
    [my.WinApi]::SetWindow($this.MainWindowHandle, $nCmdShow)
  }
  $Process | Add-Member -MemberType ScriptMethod -Name HideRunner -Value {
    $this.SetRunnerWindow(0) # 0 is the value for SW_HIDE
  }
  $Process | Add-Member -MemberType ScriptMethod -Name ShowRunner -Value {
    $this.SetRunnerWindow(1) # 1 is the value for SW_SHOWNORMAL
  }
  $Process | Add-Member -MemberType ScriptMethod -Name MinimizeRunner -Value {
    $this.SetRunnerWindow(2) # 2 is the value for SW_MINIMIZE
  }
  $Process | Add-Member -MemberType ScriptMethod -Name UnHideRunner -Value {
    $this.SetRunnerWindow(5) # 5 is the value for SW_SHOW
  }
  # Adding Watchdog process to the process object
  $Process | Add-Member -MemberType NoteProperty -Name WatchdogProcess -Value $watchdogProcess
  # Add Monitor ScriptMethod property which reports the status of the process and when it's closed.
  $Process | Add-Member -MemberType ScriptMethod -Name MonitorRunner -Value {
    if (-not $this.HasExited) {
      Write-Host "$(Get-Date)  Runner with ID $($this.Id) is running. Monitoring for exit..."
    }
    try {
      while (Get-Process -Id $this.Id -ErrorAction Stop) {
          Start-Sleep -Seconds 1
          if ($this.HasExited) {
            Write-Host "$(Get-Date)  Runner with ID $($this.Id) has exited."
            return
          }
      }
    } catch {}
    Write-Host "$(Get-Date)  Runner with ID $($this.Id) is no longer running."
  }
  # Adding kill method to the process object
  $Process | Add-Member -MemberType ScriptMethod -Name StopRunner -Value {
    Stop-Process -InputObject $this -Force
    Stop-Process -InputObject $this.WatchdogProcess -Force
    Write-Host "$(Get-Date)  Stopped runner with ID $($this.Id) and it's watchdog process with ID $($this.WatchdogProcess.Id)"
  }
  # Adding the process to the global list of eCDNRunners
  $Global:eCDNRunners += $Process
  Write-Verbose "Added new runner with ID $($Process.Id) to the global eCDNRunners list"

  if (-not $UEM_Compatible_Mode) {
    Out-Log "WARNING: The -PassThru switch enables UEM_Compatible_Mode, relying solely on the watchdog process (ID $($watchdogProcess.Id)) to terminate the runner process."
  }
  return $Process
}

if ($UEM_Compatible_Mode) {
  Out-Log ((' '*21) + "Scheduled to end at $((Get-Date).AddSeconds($ScenarioDuration)) (in $ScenarioDuration seconds)")
  Start-Sleep -Seconds 5
  if ($Process.HasExited) {
    Out-Log "ERROR: The silent runner in UEM Compatible Mode has exited unexpectedly early." -ForegroundColor Red
    Exit 5
  }
  return
}

###############
### WRAP UP ###
###############

### Waiting for the scenario duration time to elapse, then clean-up ###
# Calculate end time and loop until duration elapses, checking if process is still running
$endTime = (Get-Date).AddSeconds($ScenarioDuration)
while (($now = Get-Date) -lt $endTime) {
if ($Process.HasExited) {
    $secondsEarly = [math]::Round(($endTime - $now).TotalSeconds)
    Out-Log "$now  Chromium process with ID $($Process.Id) was terminated (about $secondsEarly sec) prematurely by an outside process."
    break
  }
  Start-Sleep -Seconds 2
}
# End process if the process is still running
if (!$Process.HasExited) {
  try {
    $stopProcessInfo = Stop-Process -InputObject $Process -Force -PassThru -ErrorAction Stop
    Out-Log "$(Get-Date)  Stopped Chromium process"
  } catch {
    Out-Log "ERROR: Failed to stop the Chromium process with ID $($Process.Id). Error: $_"
  }
}
# End watchdog process if the process is still running
if ($watchdogProcess -and !$watchdogProcess.HasExited) {
    try {
      Stop-Process -InputObject $watchdogProcess -Force
      Write-Verbose "            Stopped watchdog process"
    } catch {
      Out-Log "ERROR: Failed to stop the watchdog process with ID $($watchdogProcess.Id). Error: $_"
    } 
}
else {
  Write-Verbose "            Watchdog process with ID $($watchdogProcess.Id) has already exited."
}
if (Test-Path $preferencesFilePath) {
  try {
    $Prefs = ((Get-Content $preferencesFilePath) -replace "`"exit_type`":`"Crashed`"" , "`"exit_type`":`"none`"") -replace "`"exited_cleanly`":false","`"exited_cleanly`":true"
    Set-Content -Path $preferencesFilePath -Value $Prefs
    Set-ItemProperty -Path $preferencesFilePath -Name IsReadOnly -Value $true
  } catch {}
}
if (Test-Path $cacheFolderPath) {
  Remove-Item -Path $cacheFolderPath -Recurse -Force -ErrorAction SilentlyContinue
  Out-Log "$(Get-Date)  Cleaned up cache folder '$cacheFolderPath'"
}