# ============================================
# Скрипт: Enable MFA for AD Group Members
# Описание: Включает Per-user MFA для пользователей из локальной группы AD,
#          у которых статус Disabled. Пропускает тех, у кого уже Enabled/Enforced.
# ============================================

# 1. Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "Policy.ReadWrite.AuthenticationMethod", "UserAuthenticationMethod.Read.All"

# 2. Get users from local AD group
# REPLACE with your AD group distinguished name
$ADGroupDN = "CN=YOUR-GROUP-NAME,OU=Your-OU,DC=yourdomain,DC=com"

Write-Host "Getting users from AD group: $ADGroupDN" -ForegroundColor Cyan
try {
    $ADUsers = Get-ADGroupMember -Identity $ADGroupDN -Recursive | Where-Object {$_.objectClass -eq "user"} | Get-ADUser -Properties UserPrincipalName
} catch {
    Write-Host "Error getting AD group members. Ensure ActiveDirectory module is installed and group exists." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    exit
}

if ($ADUsers.Count -eq 0) {
    Write-Host "No users found in group." -ForegroundColor Yellow
    exit
}

Write-Host "Users found in group: $($ADUsers.Count)" -ForegroundColor Green

# 3. Iterate through users and check MFA status
$EnabledCount = 0
$SkippedCount = 0
$FailedCount = 0

foreach ($ADUser in $ADUsers) {
    $UserUPN = $ADUser.UserPrincipalName
    
    if (-not $UserUPN) {
        Write-Host "Skipping user without UPN: $($ADUser.Name)" -ForegroundColor Yellow
        $SkippedCount++
        continue
    }
    
    Write-Host "Processing user: $UserUPN" -ForegroundColor Cyan
    
    try {
        # Get current MFA status for the user
        $MFAStatusUri = "https://graph.microsoft.com/beta/users/$UserUPN/authentication/requirements"
        $MFAStatus = Invoke-MgGraphRequest -Uri $MFAStatusUri -Method GET
        
        $CurrentState = $MFAStatus.perUserMfaState
        
        Write-Host "  Current status: $CurrentState" -ForegroundColor Gray
        
        # Check if MFA needs to be enabled
        if ($CurrentState -eq "disabled") {
            Write-Host "  Status 'disabled' - enabling MFA..." -ForegroundColor Yellow
            
            # Update status to "enabled"
            $Body = @{
                perUserMfaState = "enabled"
            } | ConvertTo-Json
            
            $UpdateUri = "https://graph.microsoft.com/beta/users/$UserUPN/authentication/requirements"
            Invoke-MgGraphRequest -Uri $UpdateUri -Method PATCH -Body $Body
            
            Write-Host "  ✅ MFA successfully enabled for $UserUPN" -ForegroundColor Green
            $EnabledCount++
        } 
        elseif ($CurrentState -eq "enabled" -or $CurrentState -eq "enforced") {
            Write-Host "  ⏭️ MFA already $CurrentState — skipping" -ForegroundColor Gray
            $SkippedCount++
        } 
        else {
            Write-Host "  ⚠️ Unknown status: $CurrentState — skipping" -ForegroundColor Yellow
            $SkippedCount++
        }
    }
    catch {
        Write-Host "  ❌ Error processing $UserUPN : $_" -ForegroundColor Red
        $FailedCount++
    }
}

# 4. Display final report
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Итоговый отчет:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Всего обработано пользователей: $($ADUsers.Count)"
Write-Host "✅ MFA включена: $EnabledCount"
Write-Host "⏭️ Пропущено (уже включена/принудительная): $SkippedCount"
Write-Host "❌ Ошибок при обработке: $FailedCount"

if ($FailedCount -gt 0) {
    Write-Host "`n⚠️ Warning: There are errors. Check logs above." -ForegroundColor Yellow
}

Write-Host "`nScript completed." -ForegroundColor Green

# 5. Disconnect from Graph (optional)
Disconnect-MgGraph
