# How to Deploy the eCDN Silent Runner Script with Microsoft Intune

__Last Update Date:__ June 05, 2025  
__Created By:__ Diego Reategui  

***

Below is validated guidance on how to deploy Microsoft eCDN Silent Runners using Microsoft Intune.

> [!CAUTION]
> This guidance has been tested and proven to work but __we cannot guarantee__ it will work in your environment. Please use the following instructions as general guidance.

## 1. Procure the required scripts

Reach out to your account team for these:

- [_UEM compatible silent-tester-runner-windows.ps1_](/silent-tester-runner-windows.ps1) script
- [_detection-script.ps1_](./detection-script.ps1) script

## 2. Prepare both script templates by adapting them for your environment

1. In the _silent-tester-runner-windows.ps1_ script, ensure you set...

    - your Tenant's ID as the value for __$TenantID__
    - a new Test ID string as the value for __$TestID__
    - a runner Time-To-Live (in seconds) of your choice, as the value for __$ScenarioDuration__
    - the __$UEM\_Compatible\_Mode__ parameter to __$true__  
    See [silent testing framework documentation](https://learn.microsoft.com/ecdn/technical-documentation/silent-testing-framework#run-instructions-for-windows-environment) for more information on these variables.

2. In the _detection-script.ps1_, ensure that the value for __$TestID__ matches the value set in the runner script.

## 3. Once your scripts are adapted, go to [intune.microsoft.com](https://intune.microsoft.com/#home)

## 4. Select Devices

## 5. Select Scripts and remediation

## 6. Select Create script package

> [!NOTE]
> Requires _Windows license verification_ found in __Tenant administration__ > __Connectors and tokens__ > __Windows data__.

![Step 6 screenshot](/media/intune-step06.png)

## 7. Give it a name such as "Deploy eCDN silent runner script"

(Optional) Input a description as necessary

![Step 7 screenshot](/media/intune-step07.png)

## 8. Select Next

## 9. Before uploading scripts...

> [!IMPORTANT]
> Ensure you've adapted __BOTH__ of the scripts for your environment according to [__step 1__](#1-procure-the-required-scripts) of this guide.

## 10. Select detection-script.ps1 from file upload menu

## 11. Select silent-tester-runner-windows.ps1 from file upload menu

(Please disregard the outdated content of the test scripts depicted in the screenshots.)

![Step 11 screenshot](/media/intune-step11.png)

## 12. Run the script using... 

- the logged-on credentials, and
- in 64-bit PowerShell
![Step 12 screenshot](/media/intune-step12.png)

## 13. Select Next

## 14. Select Next

No need to set a Scope tag.

![Step 14 screenshot](/media/intune-step14.png)

## 15. Select "+ Select groups to include"

![Step 15 screenshot](/media/intune-step15.png)

## 16. Select the target group(s)

The computers (or user) contained in these groups will be executing the detection and mitigation scripts. Ie. launching the silent runner.

![Step 16 screenshot](/media/intune-step16.png)

## 17. Select the "Select" button

## 18. The group should now be displayed under "Assign to" heading

![Step 18 screenshot](/media/intune-step18.png)

## 19. Select "Daily" to modify the schedule

![Step 19 screenshot](/media/intune-step19.png)

## 20. Change the frequency to Hourly, from the pull-down menu.

![Step 20 screenshot](/media/intune-step20.png)

## 21. Select Apply

You can leave the "Repeats every" textbox with the value of "1"

## 22. Select Next

## 23. Select Create

You're done. Within the next 24 hours the scripts should run and your _silent runner_ should come online.

There are methods of triggering the script to run earlier (such as restarting the endpoints) which involve accessing the target machine(s) directly, but those methods are out of scope for this guide.

> [!TIP]
> If you have a need to instance silent runners on a cyclical, recurring basis, see the latest, provisional versions of the and _detection_ script in the [/provisional](../provisional/readme.md) folder.
