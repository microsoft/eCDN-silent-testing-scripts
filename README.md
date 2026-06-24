# Microsoft eCDN Silent Testing Runner script

This project contains the Microsoft eCDN Silent Runner script, modernized for improved flexibility, robustness, and compatibility with different environments.

- **Parameterization:** Allows more flexibility and reusability by passing arguments instead of hardcoding values.
- **UEM Compatibility:** Introduced `UEM_Compatible_Mode` switch for better compatibility with UEM solutions like SCCM and Intune.
- **Dynamic TestID:** For ease of use and repeated instancing via UEM solutions.
- **Environment:** Parameter for use with government (GCC or GCCH) tenants.
- **Validation:** Argument validation to ensure correct input formats and values.
- **Improved Logging and Error Handling:** Enhanced error messages and logging for better troubleshooting.
- **Watchdog Process:** Modified the watchdog process to include cache folder cleanup.
- **Browser Policy Detection:** Detects and warns about policies (`BrowserSignin`, `HeadlessModeEnabled`, `WebRtcIPHandling`) that may prevent the runner from operating correctly.

## Quick examples

```powershell
# Basic usage
.\silent-tester-runner-windows.ps1 -TenantID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# GCC/GCCH tenant
.\silent-tester-runner-windows.ps1 -TenantID "..." -Environment GCCH

# UEM deployment (SCCM/Intune)
.\silent-tester-runner-windows.ps1 -TenantID "..." -SCCM

# Custom duration (8 hours)
.\silent-tester-runner-windows.ps1 -TenantID "..." -Seconds 28800
```

> [!CAUTION]
> Your experience in using Silent Testing depends on many factors, including the browser version and security policies that you are using. This version of the script has been thoroughly tested and proven to work but **we cannot guarantee** it will work in your environment. Use the tool at your own risk.

The modernized runner script can be found [here](./silent-tester-runner-windows.ps1).

## Summary

The main change is with the addition of the `UEM_Compatible_Mode` switch which allows the script to exit after the silent runner (headless browser instance) is launched, relying on the child watchdog process to close the runner after the scenario duration time elapses.
Without the switch, the script stays open for the duration of the scenario, possibly causing UEMs to time out and mis-report the script as having failed.

The secondary main change is the addition of logging for the script itself, which is stored in your temp folder, in a file named `p5_script_{TestID}.txt` where **TestID** is the parameter value (for example `p5_script_Oct25Test01.txt`).

> [!TIP]
> For UEM deployment guidance, see the [**Intune** guidance](./intune/readme.md), and the [**SCCM** guidance](./sccm/readme.md).

For more information on Silent Testing, see the [framework documentation](https://learn.microsoft.com/ecdn/technical-documentation/silent-testing-framework).

## Legacy versions

For posterity, older versions of the script are archived below:

- [v2.2.17.0](./archive/silent-tester-runner-windows-v2.2.17.0.ps1) — the previous modernized version.
- [Original (legacy headless)](./archive/original/readme.md) — the non-modernized, legacy version.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
