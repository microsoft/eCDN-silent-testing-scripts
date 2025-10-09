# Provisional Silent Test Runner script update

Date: October 9th, 2025

> [!CAUTION]
> While this provisional update has passed limited testing, __we do not guarantee__ it will work in your environment or for your purposes. Use the provisional script at your own risk.

## Change log - Detection script

- Modified to support a repeating schedule / frequency
- Modified to report back to Intune the remediation script's output. Seen in the _Pre-_ and _Post-remediation detection output_ columns of the __Device status__ page.

## Change log - Runner script

- Improved logging resilience.
- Improved timeout implementation to be date/time-based so it's unaffected by the machine going into sleep or hibernate.
- Improved script to detect and log if instanced runner is terminated early.
- Updated watchdog process now uses `powershell` instead of `cmd`.
- Improved watchdog process to detect and log various conditions.
- Added detection for the Edge `BrowserSignin` policy, which can prevent the runner from operating silently.
- Added detection for the Edge `HeadlessModeEnabled` policy, which can prevent headless (silent) runner operation.
- Added detection for the Edge `WebRtcLocalhostIpHandling` policy, which can prevent the runner from reaching the backend service.
- Incremented version number.
