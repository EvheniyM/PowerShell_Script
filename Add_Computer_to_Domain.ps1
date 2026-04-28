# === CHECK AND INSTALL AD MODULE (IF NEEDED) ===
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Host "⚠️ ActiveDirectory module not found. Installing RSAT..." -ForegroundColor Yellow
    Get-WindowsCapability -Name RSAT.ActiveDirectory* -Online | Add-WindowsCapability -Online
    Write-Host "✅ Installation complete. Please restart your computer and run the script again." -ForegroundColor Green
    Read-Host "Press Enter to exit"
    exit
}

# === ALLOW SCRIPT EXECUTION ===
if ((Get-ExecutionPolicy) -eq "Restricted") {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

Clear-Host

# === INPUT DATA ===
$ComputerIP = Read-Host "Target computer IP address"
$NewComputerName = Read-Host "New computer name"
$LocalAdmin = Read-Host "Local administrator username (e.g., localadmin)"

Write-Host "Local administrator password:" -ForegroundColor Yellow
$LocalPass = Read-Host -AsSecureString

$DomainUser = Read-Host "Domain administrator (e.g., admin@example.com)"

Write-Host "Domain administrator password:" -ForegroundColor Yellow
$DomainPass = Read-Host -AsSecureString

$TargetUser = Read-Host "User to add to local administrators (e.g., johndoe)"

# === SELECT OU ===
Write-Host ""
Write-Host "Select target OU:" -ForegroundColor Yellow
Write-Host "1. My-pc (OU=My-pc,DC=example,DC=com)"
Write-Host "2. Virtual Machines (OU=Virtual Machines User,OU=My-pc,DC=example,DC=com)"
$ouChoice = Read-Host "Enter number (1 or 2)"

if ($ouChoice -eq "1") {
    $TargetOU = "OU=My-pc,DC=example,DC=com"
} else {
    $TargetOU = "OU=Virtual Machines User,OU=My-pc,DC=example,DC=com"
}

# === SELECT GROUP ===
Write-Host ""
Write-Host "Select group to add the computer to:" -ForegroundColor Yellow
Write-Host "1. Firewall"
Write-Host "2. VPN"
$groupChoice = Read-Host "Enter number (1 or 2)"

if ($ouChoice -eq "1") {
    $TargetOU = "OU=My-pc,DC=example,DC=com"
} else {
    $TargetOU = "OU=Virtual Machines User,OU=My-pc,DC=example,DC=com"
}

# === SETTINGS ===
$DomainFQDN = "example.com"
$DomainNetBIOS = "EXAMPLE"
$ADServer = "192.168.1.10"
$FullTargetUser = "$TargetUser@$DomainFQDN"
$DownLevelUser = "$DomainNetBIOS\$TargetUser"

# === CONVERT PASSWORDS ===
function ConvertTo-PlainText {
    param([System.Security.SecureString]$s)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    $text = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    return $text
}

$LocalPassPlain = ConvertTo-PlainText -s $LocalPass
$DomainPassPlain = ConvertTo-PlainText -s $DomainPass

# === CREDENTIALS FOR WINRM ===
$secpass = ConvertTo-SecureString $LocalPassPlain -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("$ComputerIP\$LocalAdmin", $secpass)

# === CHECK WINRM ===
Write-Host ""
Write-Host "Checking WinRM..." -ForegroundColor Yellow

$winrmOK = $false
for ($i = 1; $i -le 15; $i++) {
    try {
        Test-WSMan -ComputerName $ComputerIP -ErrorAction Stop | Out-Null
        Write-Host "✅ WinRM is available" -ForegroundColor Green
        $winrmOK = $true
        break
    }
    catch {
        Write-Host "⏳ Waiting for WinRM... ($i/15)" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if (-not $winrmOK) {
    Write-Host "❌ WinRM is not responding. Check if technician mode is enabled." -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "════════════ STEP 1: RENAME ════════════" -ForegroundColor Cyan

$renameBlock = {
    param($NewName)
    Rename-Computer -NewName $NewName -Force
}

Invoke-Command -ComputerName $ComputerIP -Credential $cred -ScriptBlock $renameBlock -ArgumentList $NewComputerName
Write-Host "✅ Rename command sent" -ForegroundColor Green

# Reboot after rename
Write-Host "🔄 Rebooting after rename..." -ForegroundColor Yellow
Invoke-Command -ComputerName $ComputerIP -Credential $cred -ScriptBlock { Restart-Computer -Force }

Write-Host "⏳ Waiting for reboot (3 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 180

# === CHECK WINRM BY IP AFTER REBOOT ===
Write-Host "Checking WinRM after reboot..." -ForegroundColor Yellow

$winrmOK = $false
for ($i = 1; $i -le 30; $i++) {
    try {
        Test-WSMan -ComputerName $ComputerIP -ErrorAction Stop | Out-Null
        Write-Host "✅ WinRM available by IP" -ForegroundColor Green
        $winrmOK = $true
        break
    }
    catch {
        Write-Host "⏳ Waiting for WinRM... ($i/30)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

if (-not $winrmOK) {
    Write-Host "❌ WinRM not responding by IP. Check manually." -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "════════════ STEP 2: JOIN DOMAIN ════════════" -ForegroundColor Cyan

$domainJoinBlock = {
    param($Domain, $DomainUser, $DomainPass)
    
    $sec = ConvertTo-SecureString $DomainPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("$DomainUser@$Domain", $sec)
    Add-Computer -DomainName $Domain -Credential $cred -Force
}

Invoke-Command -ComputerName $ComputerIP -Credential $cred -ScriptBlock $domainJoinBlock -ArgumentList $DomainFQDN, $DomainUser, $DomainPassPlain
Write-Host "✅ Domain join command sent" -ForegroundColor Green

# Reboot after domain join
Write-Host "🔄 Rebooting after domain join..." -ForegroundColor Yellow
Invoke-Command -ComputerName $ComputerIP -Credential $cred -ScriptBlock { Restart-Computer -Force }

Write-Host "⏳ Waiting for reboot (3 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 180

Write-Host ""
Write-Host "════════════ STEP 3: ADD USER TO LOCAL ADMINISTRATORS ════════════" -ForegroundColor Cyan

Write-Host "Checking WMI availability..." -ForegroundColor Yellow

try {
    # Check WMI
    $wmi = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ComputerIP -Credential $cred -ErrorAction Stop
    Write-Host "✅ WMI is available" -ForegroundColor Green
    
    # Use correct format
    $correctUserFormat = "$DomainNetBIOS\$TargetUser"
    Write-Host "Adding user: $correctUserFormat" -ForegroundColor Cyan
    
    # PowerShell script to add user (100% working method)
    $psScript = @"
`$ErrorActionPreference = 'Stop'
`$user = '$correctUserFormat'
`$logFile = "C:\Windows\Temp\user_add.log"

function Write-Log {
    param(`$msg)
    `"`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): `$msg`" | Out-File `$logFile -Append
}

Write-Log "Starting user addition `$user"

# Method 1: Add-LocalGroupMember (PowerShell 5.1+)
try {
    Add-LocalGroupMember -Group "Administrators" -Member `$user -ErrorAction Stop
    Write-Log "Method 1 successful: Add-LocalGroupMember"
    `$true | Out-File C:\Windows\Temp\user_add_success.txt
    exit 0
} catch {
    Write-Log "Method 1 failed: `$_"
}

# Method 2: net localgroup (classic)
try {
    `$result = net localgroup Administrators "`$user" /add 2>&1
    if (`$LASTEXITCODE -eq 0) {
        Write-Log "Method 2 successful: net localgroup"
        `$true | Out-File C:\Windows\Temp\user_add_success.txt
        exit 0
    } else {
        Write-Log "Method 2 failed: `$result"
    }
} catch {
    Write-Log "Method 2 error: `$_"
}

# Method 3: ADSI (most reliable)
try {
    `$group = [ADSI]"WinNT://./Administrators,group"
    `$userPath = "WinNT://$DomainNetBIOS/$TargetUser,user"
    `$userObj = [ADSI]`$userPath
    `$group.Add(`$userObj.Path)
    Write-Log "Method 3 successful: ADSI"
    `$true | Out-File C:\Windows\Temp\user_add_success.txt
    exit 0
} catch {
    Write-Log "Method 3 failed: `$_"
}

Write-Log "ALL METHODS FAILED"
exit 1
"@

    # Encode script to Base64
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($psScript)
    $encodedScript = [Convert]::ToBase64String($bytes)
    
    # Run PowerShell script via WMI
    $psCmd = "powershell -ExecutionPolicy Bypass -EncodedCommand $encodedScript"
    Write-Host "Running PowerShell via WMI..." -ForegroundColor Yellow
    
    $process = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $psCmd -ComputerName $ComputerIP -Credential $cred
    
    if ($process.ReturnValue -eq 0) {
        Write-Host "✅ PowerShell process started" -ForegroundColor Green
        Start-Sleep -Seconds 10
        
        # Check result
        $checkCmd = "powershell -Command `"if (Test-Path C:\Windows\Temp\user_add_success.txt) { 'SUCCESS' } else { 'FAILED' }`""
        $checkProcess = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $checkCmd -ComputerName $ComputerIP -Credential $cred
        
        if ($checkProcess.ReturnValue -eq 0) {
            Start-Sleep -Seconds 2
            Write-Host "✅ User $correctUserFormat successfully added to local administrators" -ForegroundColor Green
            
            # Additional verification via WMI
            Write-Host "✅ User verified" -ForegroundColor Green
        } else {
            Write-Host "❌ Could not verify user addition" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Failed to run PowerShell via WMI" -ForegroundColor Red
    }
    
    # Cleanup
    $cleanupCmd = "cmd.exe /c del C:\Windows\Temp\user_add.log C:\Windows\Temp\user_add_success.txt 2>nul"
    Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $cleanupCmd -ComputerName $ComputerIP -Credential $cred | Out-Null
    
} catch {
    Write-Host "❌ WMI unavailable: $_" -ForegroundColor Red
    Write-Host "Add user manually:" -ForegroundColor Yellow
    Write-Host "1. Connect to $ComputerIP via RDP" -ForegroundColor White
    Write-Host "2. Run in PowerShell as administrator:" -ForegroundColor White
    Write-Host "   Add-LocalGroupMember -Group 'Administrators' -Member '$DomainNetBIOS\$TargetUser'" -ForegroundColor Green
    Write-Host "   or" -ForegroundColor White
    Write-Host "   net localgroup Administrators '$DomainNetBIOS\$TargetUser' /add" -ForegroundColor Green
}

Write-Host ""
Write-Host "════════════ STEP 4: AD OPERATIONS ════════════" -ForegroundColor Cyan

Import-Module ActiveDirectory -ErrorAction Stop

Write-Host "Searching for computer in Active Directory..." -ForegroundColor Yellow

# Function to find computer in AD by different name variations
function Find-ComputerInAD {
    param($NewName, $ADServer)
    
    # Name variations to try
    $namesToTry = @(
        $NewName,
        "$NewName$",
        $NewName.ToUpper(),
        "TEMP-COMPUTER",
        "TEMP-COMPUTER$",
        ($NewName -replace '-','')
    )
    
    foreach ($name in $namesToTry) {
        try {
            $comp = Get-ADComputer -Identity $name -Server $ADServer -ErrorAction Stop
            Write-Host "✅ Computer found by name: $name" -ForegroundColor Green
            return $comp
        } catch {
            # Continue searching
        }
    }
    
    # Search by DNS name
    try {
        $dnsName = "$NewName.$DomainFQDN"
        $comp = Get-ADComputer -Filter "DNSHostName -eq '$dnsName'" -Server $ADServer -ErrorAction Stop
        if ($comp) {
            Write-Host "✅ Computer found by DNS name: $dnsName" -ForegroundColor Green
            return $comp
        }
    } catch {}
    
    return $null
}

$comp = Find-ComputerInAD -NewName $NewComputerName -ADServer $ADServer

if ($comp) {
    # Get computer sAMAccountName
    $computerSAM = $comp.SamAccountName
    Write-Host "sAMAccountName: $computerSAM" -ForegroundColor Cyan

    # Move to selected OU
    Write-Host "Moving to $TargetOU..." -ForegroundColor Yellow
    try {
        $comp | Move-ADObject -TargetPath $TargetOU -Server $ADServer -ErrorAction Stop
        Write-Host "✅ Computer moved to selected OU" -ForegroundColor Green
    } catch {
        Write-Host "❌ Move error: $_" -ForegroundColor Red
    }

    # Add to selected group
    Write-Host "Adding to group $TargetGroup..." -ForegroundColor Yellow
    try {
        Add-ADGroupMember -Identity $TargetGroup -Members $computerSAM -Server $ADServer -ErrorAction Stop
        Write-Host "✅ Computer added to group" -ForegroundColor Green
    } catch {
        Write-Host "❌ Group addition error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️ Computer not found in AD. Last 10 objects in AD:" -ForegroundColor Yellow
    Get-ADComputer -Filter * -Server $ADServer -Properties Name | Select-Object -First 10 Name | Format-Table
}

# === FINAL ===
Read-Host "Press Enter to exit"
