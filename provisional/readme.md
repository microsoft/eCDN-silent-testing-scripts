# Provisional Silent Test Runner script update

Date: October 9th, 2025

> [!CAUTION]
> While this provisional update has passed limited testing, __we do not guarantee__ it will work in your environment or for your purposes. Use the provisional script at your own risk.

## Change log - [Detection script](./detection-script.ps1)

- Added enhanced configuration guidance.
- Added support a repeating schedule / frequency.
- Modified to report back to Intune the remediation script's output. Seen in the _Pre-_ and _Post-remediation detection output_ columns of the __Device status__ page.
- Modified to report back to Intune, upon compliance detected, the latest remediation script's output.
- Improved output formatting using `|` as a delimiter for easy of parsing.

## Change log - [Runner script](./silent-tester-runner-windows.ps1)

- Improved logging resilience, with retry logic (up to 3 attempts with 300ms delays).
- Improved timeout implementation. Changed from simple `Start-Sleep -s $ScenarioDuration` to date/time-based loop that's unaffected by sleep/hibernate.
- Improved script to detect and log if instanced runner is terminated early.
- Updated watchdog process now uses `powershell` instead of `cmd` to enable enhanced monitoring and progress reporting.
- Improved watchdog process to detect and log various conditions.
- Added browser policy detection:
    - For the `BrowserSignin` policy, which can prevent the runner from operating silently.
    - For the Edge `HeadlessModeEnabled` policy, which can prevent headless (silent) runner operation.
    - For the Edge `WebRtcLocalhostIpHandling` and Chrome `WebRtcIPHandling` which can prevent the runner from reaching the backend service.
- Improved to generate Warning and Error messaging which can be captured by Intune.
- Incremented version number.
