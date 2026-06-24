# Changelog — v2.3 scripts

Date: November 12th, 2025

## Runner script changes (from v2.2.17.0 to v2.3.9.1)

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

## Detection script changes (from v2.2 to v2.3)

- Added enhanced configuration guidance.
- Added support for a repeating schedule / frequency.
- Modified to report back to Intune the remediation script's output. Seen in the _Pre-_, _Post-remediation detection output_ and _Remediation error_ columns of the __Device status__ page.
- Modified to report back to Intune, upon compliance detected, the latest remediation script's output.
- Improved output formatting using `|` as a delimiter for ease of parsing.
