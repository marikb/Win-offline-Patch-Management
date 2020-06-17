![Disconnected WSUS Servers](https://docs.microsoft.com/de-de/security-updates/windowsupdateservices/images/cc708628.970fd502-ce48-4a7b-a0f4-7a7c6eb5b36a%28ws.10%29.gif)

# Disconnected Network Windows Patch Management Export Import
Two script for file export and file import of patches from Windows Update for WSUS servers.

Export.ps1 - WSUS server connected to Windows Updates<br />
Import.ps1 - WSUS server located in your disconnected environment.<br />

# WSUS configuration requirments

###Validate both WSUS servers have same:<br />
I. Products and Classifications<br />
II. Update files and languages<br />
III. Set Express<br />


### IIS Application Pools (Disconnected WSUS):<br />
  ⦁	Increase the WsusPool Queue Length to 25000<br />
  ⦁	Increase the WsusPool Private Memory limit set to 0 (unlimited)<br />
  ⦁	In AppPool of WSUSPool change Regular Time Interval (Minutes) to 0<br />
  
### Modify httpRunTime by adding an executionTimeout attribute:<br />
  \<httpRuntime maxRequestLength="4096" executionTimeout="3600"\>
<br />

### Configure to SUP - additional permissions to allow the WSUS Configuration Manager<br />
  ⦁	Add the SYSTEM account to the WSUS Administrators group<br />
  ⦁	Add the NT AUTHORITY\SYSTEM account as a user for the WSUS database (SUSDB). Configure a minimum of the webService database role membership.<br />


### SSL Configuration<br />
  ⦁	Create a certificate for the hostname (Optional to SQL too)<br />
  ⦁	Import into server via wusa ctl.<br />
  ⦁	Open port 8531 to all clients<br />

# How to run

Copy Export folder for connected  updates and Import folder to disconnected server.<br />

Connected WSUS to Windows Updates:<br />
  ⦁	Run sync <br />
  ⦁	Run script to create bulk, make sure deny and approve configured as desired.<br />

Disconnected WSUS (in your disconnected network):<br />
  ⦁	Copy created bulk folder to Import folder<br />
  ⦁	Run script <br />


# Additional sources

⦁ Best Practices with Windows Server Update Services - https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc720525(v=ws.10)<br />

⦁ SUP configuration - https://everythingsccm.com/2017/03/27/configuring-wsus-with-sccm-current-branch-server-2016-part-i/
                      https://docs.microsoft.com/en-us/sccm/sum/understand/software-updates-introduction#BKMK_SUMCompliance<br />

