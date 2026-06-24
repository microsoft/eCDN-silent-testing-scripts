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
$ScriptVersion = "2.2.17.0"
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
function Write-OutputOrHost {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Object,
        [ConsoleColor]$ForegroundColor = 'White'
    )
    if ($UEM_Compatible_Mode) {
        Write-Output $Object
    } else {
        # Check the first word to determine the appropriate Write- command
        $firstWord = ($Object -split '\s+')[0].TrimEnd(':')
        switch ($firstWord.ToUpper()) {
            'ERROR'   { Write-Error ($Object = "$(Get-Date)  $Object") }
            'WARNING' { Write-Warning ($Object = "$(Get-Date)  $Object") }
            default   { Write-Host $Object -ForegroundColor $ForegroundColor }
        }
    }
    try {
      Add-Content -Path $scriptLogPath -Value $Object -Encoding UTF8 -ErrorAction Stop
    } catch {
      Write-Output "Failed to write to log file '$scriptLogPath'. Error: $_"
    }
}

### Parameter validation ###
if ($TestID -notmatch '^[a-zA-Z0-9_\-]+$') {
  Write-Error "Invalid Parameter: Test ID. Please provide a valid Test ID containing only alphanumeric characters, underscores, or hyphens."
  Exit 1
}
$RegexForTenantId = '^[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}$'
if ($TenantID -notmatch $RegexForTenantId) {
  Write-OutputOrHost "ERROR: Invalid Parameter: Tenant ID '$TenantID'. Please provide a valid Tenant ID."
  Exit 1
}
if ($ScenarioDuration -lt $durationMinimum) {
  Write-OutputOrHost "ERROR: Invalid Parameter: Scenario Duration '$ScenarioDuration'. Please provide a Scenario Duration of greater than $durationMinimum seconds."
  Exit 1
}
if ($CustomChromiumPath -and !(Test-Path $CustomChromiumPath)) {
  Write-OutputOrHost "ERROR: Invalid Parameter: Custom Chromium Path '$CustomChromiumPath'. Please provide a valid path to the Chromium executable."
  Exit 1
}

### Checking if the script is already running on this machine with the same TestID ###
if ((Test-Path $logPath) -and (!$AllowMultipleRuns)) {
  Write-OutputOrHost "ERROR: Test '$TestID' already ran on this machine. aborting"
  Exit 0
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
Write-OutputOrHost "Script version: $ScriptVersion"
Write-OutputOrHost "Test ID: $TestID"
Write-OutputOrHost "Adapter ID: $AdapterId"

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
    Write-OutputOrHost "Could not find Edge or Chrome executable. Please set the `$CustomChromiumPath variable in the script to your Chromium browser's executable path."
    Exit 2
  }

  if ($PreferChrome -and $CustomChromiumPath -notmatch "chrome\.exe") {
    Write-OutputOrHost "Chrome not found" -ForegroundColor DarkGray
  }
}
Write-OutputOrHost "Using Chromium at path '$CustomChromiumPath'"

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
Write-OutputOrHost "$(($startedAt=Get-Date))  Started Chromium $($Process.Name) process, with id: $($Process.id)"
# Swapping old window hide method with the --headless flag, as it doesn't work with the headless flag and will just indefinitely loop while it waits for the window to get a WindowHandle assigned.  Which it won't since it's headless.
if ($OldHideMethod -and -not $DirectRunner -and [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {
  While ($Process.MainWindowHandle -eq 0 -and ($elapsed=(Get-Date) - $startedAt).TotalSeconds -lt 3) { Start-Sleep -m 100 }
  [my.WinApi]::Hide($Process.MainWindowHandle)
  Write-Host "Window hidden after $elapsed" -F DarkGray
}

### Setting up the watchdog process ###
$chromePid = $Process.id
$cmd = "cmd.exe"
$extraTimeout = $ScenarioDuration + 10
# Watchdog process:
$argos = @(
  # - waits for the specified scenario duration time
  "/v:on /c timeout $extraTimeout",
  # - checks if the Chromium process is still running
  "&& (tasklist /FI `"PID eq $chromePid`" | findstr $chromePid >nul)",
  # - if it is, it kills the process and logs the action, or logs that it failed to do so
  "&& (taskkill.exe /f /t /pid $chromePid && echo !date:~4! !time:~0,8!  Watchdog ended chromium process >> `"$scriptLogPath`"  || echo !date:~4! !time:~0,8!  Watchdog failed to end chromium process >> `"$scriptLogPath`")",
  # - if the process is not running, it logs that the process was not found
  "|| (echo !date:~4! !time:~0,8!  PID $chromePid not found by Watchdog >> `"$scriptLogPath`")",
  # - finally, removes the cache folder
  "& rd /s /q `"$cacheFolderPath`"")
$watchdogProcess = Start-Process $cmd -WindowStyle hidden -ArgumentList $argos -Passthru
Write-Verbose "            Started Watchdog process, with id: $($watchdogProcess.id)"

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
    Write-OutputOrHost "WARNING: The -PassThru switch enables UEM_Compatible_Mode, relying solely on the watchdog process (ID $($watchdogProcess.Id)) to terminate the runner process."
  }
  return $Process
}

if ($UEM_Compatible_Mode) {
  Write-OutputOrHost ((' '*21) + "Scheduled to end at $((Get-Date).AddSeconds($ScenarioDuration)) (in $ScenarioDuration seconds)")
  Start-Sleep -Seconds 5
  return
}

###############
### WRAP UP ###
###############

### Waiting for the scenario duration time to elapse, then clean-up ###
Start-Sleep -s $ScenarioDuration
# Check if the process is still running
if ($Process.HasExited) {
  Write-OutputOrHost "$(Get-Date)  Chromium process with ID $($Process.Id) has already exited."
} else {
  Write-OutputOrHost "$(Get-Date)  Ending Chromium process with ID $($Process.Id)"
  try {
    $stopProcessInfo = Stop-Process -InputObject $Process -Force -PassThru -ErrorAction Stop
    Write-OutputOrHost "$(Get-Date)  Stopped Chromium process"
    Stop-Process -InputObject $watchdogProcess -Force -ErrorAction SilentlyContinue
  } catch {
    Write-OutputOrHost "Failed to stop the Chromium process with ID $($Process.Id). Error: $_"
  }
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
  Write-OutputOrHost "$(Get-Date)  Cleaned up cache folder at $cacheFolderPath"
}