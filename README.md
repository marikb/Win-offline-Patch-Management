# Disconnected Network Windows Patch Management Export Import
Two script for file export and file import of patches from Windows Update for WSUS servers.

Export.ps1 - WSUS server connected to Windows Updates
Import.ps1 - WSUS server located in your disconnected environment.

Architecture:
![Disconnected WSUS Servers](https://docs.microsoft.com/de-de/security-updates/windowsupdateservices/images/cc708628.970fd502-ce48-4a7b-a0f4-7a7c6eb5b36a%28ws.10%29.gif)


# WSUS configuration requirments

Validate both WSUS servers have same:
  i.	 Products and Classifications
  ii.	 Update files and languages
  iii. Set Express

IIS Application Pools:
  ⦁	Increase the WsusPool Queue Length to 25000
  ⦁	Increase the WsusPool Private Memory limit set to 0 (unlimited
  
Modify httpRunTime by adding an executionTimeout attribute:
  ⦁	<httpRuntime maxRequestLength="4096" executionTimeout="3600" />
  ⦁	In AppPool of WSUSPool change Regular Time Interval (Minutes) to 0
⦁	

Configure to SUP - additional permissions to allow the WSUS Configuration Manager
  ⦁	Add the SYSTEM account to the WSUS Administrators group
  ⦁	Add the NT AUTHORITY\SYSTEM account as a user for the WSUS database (SUSDB). Configure a minimum of the webService database role membership.


SSL Configuration
  ⦁	Create a certificate for the hostname (Optional to SQL too)
  ⦁	Import into server via wusa ctl.
  ⦁	Open port 8531 to all clients

# How to run

Copy Export folder for connected  updates and Import folder to disconnected server.

Connected WSUS to Windows Updates:
  ⦁	Run sync 
  ⦁	Run script to create bulk, make sure deny and approve configured as desired.

Disconnected WSUS (in your disconnected network):
  ⦁	Copy created bulk folder to Import folder
  ⦁	Run script 


# Additional sources

⦁ Best Practices with Windows Server Update Services - https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc720525(v=ws.10)

⦁ SUP configuration - https://everythingsccm.com/2017/03/27/configuring-wsus-with-sccm-current-branch-server-2016-part-i/
                      https://docs.microsoft.com/en-us/sccm/sum/understand/software-updates-introduction#BKMK_SUMCompliance

