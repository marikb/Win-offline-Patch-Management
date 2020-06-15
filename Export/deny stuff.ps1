<#
    Deny section, add type of updates to deny here.
#>

$u = Get-WsusUpdate -approval anyexceptdeclined;

# Deny itanium
$part = @();
$part = $u | Where-object {$_.update.title -ilike "*itanium*"};
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

# Deny windows 10 versions
$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10*x86*"};
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10 pro*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10 education*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10 enterprise n*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10 team*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10*version 1511*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike "*Windows 10 build 15042*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

# Deny preview packages
$part = @();
$part = $u | Where-object {$_.update.title -ilike "*preview*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

# Deny lang of no use
$part = @();
$part = $u | Where-object {$_.update.title -ilike "*language*demand*" -and $_.update.title -inotlike "*he-il*" -and $_.update.title -inotlike "*en-us*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

$part = @();
$part = $u | Where-object {$_.update.title -ilike ("*language*"+'`['+"*"+'`]'+"*") -and $_.update.title -inotlike "*he-il*" -and $_.update.title -inotlike "*en-us*"}
$part | Deny-WsusUpdate;
$u = $u | Where-object {$_ -notin $part}

# Deny superseded
# $super = @();
# $super = ($u | Where-object {$_.UpdatesSupersedingThisUpdate  -inotlike "*none*"})
# $super | Deny-WsusUpdate
# $super.Name

Invoke-WsusServerCleanup -DeclineExpiredUpdates -DeclineSupersededUpdates;
Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles;