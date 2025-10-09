$TenantID = "TENANT_ID" # Replace TENANT_ID with you actual Microsoft Tenant Id
$TestID = "TEST_ID" # Replace with TEST_ID Which Must be different for each test
$pageURL = "https://st-sdk.ecdn.teams.microsoft.com/?customerId=${TenantID}&adapterId=PowerShell"
$scenarioDuration = 86400 # defaults to 24 hours - can be changed
$runOnce = $true # Set to $false if you want to be able to run more the one time on the machine. 2 tabs might jump to user.
$customChromePath = ""
$logPath = "$env:TEMP\p5_log_" + $TestID + ".txt"
$errLogPath = "$env:TEMP\p5_err_" + $TestID + ".txt"
$p5UserDataDir = "$env:TEMP\p5-user-" + $TestID
$preferencesFilePath = $p5UserDataDir + "\Default\Preferences"
$cacheFolderPath = $p5UserDataDir + "\Default\Cache"
$defaultPaths = @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe","C:\Program Files (x86)\Google\Chrome\Application\chrome.exe", "C:\Program Files\Google\Chrome\Application\chrome.exe")

if ((Test-Path $logPath) -and $runOnce) {
  Write-Host "$(Get-Date)  Test $TestID already ran on this machine. Aborting..."
  Exit 1
}
if (!$customChromePath -or !(Test-Path $customChromePath)) {
  try {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe') {
      $edgeExe = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' "(default)"
    }
  }
  catch {
    # do nothing
  }
  if ($edgeExe) {
    $customChromePath = $edgeExe
  }
  else {
    for($i = 0; $i -le $defaultPaths.Count; $i++ ) {
      if ($defaultPaths[$i] -and (Test-Path $defaultPaths[$i])) {
        $customChromePath = $defaultPaths[$i]
        break
      }
    }
  }
  if (!$customChromePath) {
    Write-Host "Could not find Edge or Chrome executable (chrome.exe), Please set `$customChromePath variable in the script to your Chrome executable path"
    Exit 1
  }
}
Write-Verbose "Found Chromium executable at $customChromePath"
$Process = Start-Process -RedirectStandardOutput $logPath -RedirectStandardError $errLogPath -passthru $customChromePath -ArgumentList "$($pageURL) --headless=new --use-fake-ui-for-media-stream --no-default-browser-check --disable-first-run-ui --hide-crash-restore-bubble --autoplay-policy=no-user-gesture-required --disable-backgrounding-occluded-windows --disable-background-media-suspend --disable-renderer-backgrounding --disable-gpu --remote-debugging-port=0 --disable-infobars --disable-restore-session-state --user-data-dir=$p5UserDataDir --disable-gesture-requirement-for-media-playback --disable-background-networking --disable-background-timer-throttling --disable-breakpad --disable-client-side-phishing-detection --disable-default-apps --disable-dev-shm-usage --disable-extensions --disable-field-trial-config --disable-features=msEdgeSyncSettings,msProfileStartupDialog,site-per-process,WebRtcHideLocalIpsWithMdns --disable-hang-monitor --disable-popup-blocking --disable-prompt-on-repost --disable-sync --disable-translate --metrics-recording-only --no-first-run --safebrowsing-disable-auto-update --enable-automation --password-store=basic --use-mock-keychain --mute-audio --process-per-site" -WorkingDirectory $env:TEMP
Write-Host "$(Get-Date)  Started Chromium process, with id: $($Process.id)"
$chromePid = $Process.id
$cmd = "cmd.exe"
$extraTimeout = $scenarioDuration + 10
$argos =  "/c timeout ${extraTimeout} && taskkill.exe /f /t /pid ${chromePid}"
$watchdogProcess = Start-Process -WindowStyle hidden -passthru $cmd -ArgumentList $argos
Start-Sleep -s $scenarioDuration
$stopProcessInfo = Stop-Process -InputObject $Process -passthru
$stopProcessInfo
if (Test-Path $preferencesFilePath) {
  try {
    $Prefs = ((Get-Content $preferencesFilePath) -replace "`"exit_type`":`"Crashed`"" , "`"exit_type`":`"none`"") -replace "`"exited_cleanly`":false","`"exited_cleanly`":true"
    Set-Content -Path $preferencesFilePath -Value $Prefs
    Set-ItemProperty -Path $preferencesFilePath -Name IsReadOnly -Value $true
  } catch {}
}
if (Test-Path $cacheFolderPath) {
  try {
    Remove-Item -Recurse $cacheFolderPath
  } catch {}
}
Write-Host "$(Get-Date)  Stopped Chromium process"
