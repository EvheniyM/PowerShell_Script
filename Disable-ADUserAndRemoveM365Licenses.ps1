# ============================================
# Script: Disable-ADUserAndRemoveM365Licenses.ps1
# Description: Отключает пользователя в локальном AD, очищает атрибуты,
#              удаляет из групп, перемещает в OU отключенных и удаляет лицензии M365
# ============================================

# ЗАМЕНИТЕ на реальные значения
$UserLogin = "username.surname"  # Пример: john.doe
$TargetOU = "OU=Disabled Users,OU=DisabledObjects,DC=yourdomain,DC=com"  # Пример OU

Import-Module ActiveDirectory
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Users.Actions
Import-Module Microsoft.Graph.Identity.DirectoryManagement

try {
    # ======== ЛОКАЛЬНЫЙ AD ==========
    $User = Get-ADUser -Filter "SamAccountName -eq '$UserLogin'" -Properties *

    if ($User) {
        Write-Output "Найдена учетная запись: $($User.DistinguishedName)"

        # Отключаем
        Disable-ADAccount -Identity $User
        Write-Output "Учетная запись $UserLogin отключена."

        # Очищаем атрибуты
        Set-ADUser -Identity $User -Clear mail,title,department,company,manager,mobile
        Write-Output "Атрибуты очищены."

        # Группы
        $allGroups = Get-ADPrincipalGroupMembership -Identity $User | `
            Where-Object { $_.Name -ne 'Domain Users' }

        if ($allGroups -and $allGroups.Count -gt 0) {
            try {
                Remove-ADPrincipalGroupMembership -Identity $User -MemberOf $allGroups -Confirm:$false -ErrorAction Stop
                Write-Output "Пользователь удалён из всех групп ($($allGroups.Count))."
            }
            catch {
                Write-Output "Ошибка массового удаления: $($_.Exception.Message). Пробую по одной группе..."

                foreach ($grp in $allGroups) {
                    try {
                        Remove-ADGroupMember -Identity $grp -Members $User -Confirm:$false -ErrorAction Stop
                        Write-Output "Удалён из группы: $($grp.Name)"
                    }
                    catch {
                        Write-Output "Ошибка при удалении из группы '$($grp.Name)': $($_.Exception.Message)"
                    }
                }
            }
        }
        else {
            Write-Output "У пользователя нет членств в группах (кроме Domain Users)."
        }

        # Перемещаем в Disabled OU
        Move-ADObject -Identity $User.DistinguishedName -TargetPath $TargetOU
        Write-Output "Перемещен в $TargetOU."

        # ======== MICROSOFT GRAPH вместо AzureAD ==========
        Write-Output "Подключаю Microsoft Graph..."
        Connect-MgGraph -Scopes "User.ReadWrite.All","Directory.ReadWrite.All"

        $upn = $User.UserPrincipalName
        $AzureUser = Get-MgUser -Filter "userPrincipalName eq '$upn'"

        if ($AzureUser) {
            Write-Output "Пользователь найден в Azure AD: $upn"

            # Лицензии пользователя
            $licenseDetails = Get-MgUserLicenseDetail -UserId $AzureUser.Id

            if ($licenseDetails -and $licenseDetails.Count -gt 0) {
                $licensesToRemove = $licenseDetails | Select-Object -ExpandProperty SkuId

                Write-Output "Найдено прямых лицензий: $($licensesToRemove.Count). Удаляю..."

                # Удаление прямых лицензий
                Set-MgUserLicense -UserId $AzureUser.Id -RemoveLicenses $licensesToRemove -AddLicenses @()
                Write-Output "Все прямые лицензии удалены."
            }
            else {
                Write-Output "Прямых лицензий нет (Get-MgUserLicenseDetail пуст)."
            }
        }
        else {
            Write-Output "Не найден в AzureAD (UPN: $upn)."
        }

        Write-Output "=== Готово ==="
    }
    else {
        Write-Output "Пользователь $UserLogin не найден в локальном AD."
    }
}
catch {
    Write-Output "Ошибка: $($_.Exception.Message)"
}
