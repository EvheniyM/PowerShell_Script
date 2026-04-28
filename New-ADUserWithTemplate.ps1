# ============================================
# Script: New-ADUserWithTemplate.ps1
# Description: Создает нового пользователя в Active Directory с заданными атрибутами,
#              добавляет в группы и назначает руководителя
# ============================================

# ========== КОНФИГУРАЦИЯ - ЗАМЕНИТЕ НА РЕАЛЬНЫЕ ДАННЫЕ ==========
$firstName = "FirstName"      # Пример: John
$lastName = "LastName"        # Пример: Doe
$login = "username"           # Пример: john.doe
$password = ConvertTo-SecureString "YourComplexPassword123!" -AsPlainText -Force
$phoneNumber = "380XXXXXXXXX"  # Пример: 380501111111
$email = "$login@yourdomain.com"  # Пример: john.doe@yourdomain.com

$ouPath = "OU=Staff,DC=yourdomain,DC=com"  # Пример: OU=Users,DC=company,DC=com

$otherAttributes = @{
    'title' = 'Job Title'           # Пример: Software Engineer
    'department' = 'Department'     # Пример: IT
    'company' = 'CompanyName'       # Пример: T18
}

# ========== СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ ==========
$user = New-ADUser -Name "$firstName $lastName" -GivenName $firstName -Surname $lastName -SamAccountName $login -AccountPassword $password -Enabled $true -Path $ouPath -OfficePhone $phoneNumber -EmailAddress $email -ChangePasswordAtLogon $false -OtherAttributes $otherAttributes

if ($?) {
    # Установка UserPrincipalName
    $userPrincipalName = "$login@yourdomain.com"  # Пример: username@company.com
    Set-ADUser -Identity $login -UserPrincipalName $userPrincipalName
    Enable-ADAccount -Identity $login

    # ========== ДОБАВЛЕНИЕ В ГРУППЫ ==========
    # Раскомментируйте нужные группы и добавьте свои
    Add-ADGroupMember -Identity "YOUR-GROUP-NAME" -Members $login
    #Add-ADGroupMember -Identity "Group2" -Members $login
    #Add-ADGroupMember -Identity "Group3" -Members $login

    # Дополнительные атрибуты
    Set-ADUser -Identity $login -Mobile $phoneNumber
    Set-ADUser -Identity $login -DisplayName "$firstName $lastName"

    # ========== НАЗНАЧЕНИЕ РУКОВОДИТЕЛЯ ==========
    # Укажите логин руководителя (раскомментируйте нужного)
    # $manager = Get-ADUser -Filter {SamAccountName -eq "manager.username1"}
    $manager = Get-ADUser -Filter {SamAccountName -eq "manager.username2"}
    # $manager = Get-ADUser -Filter {SamAccountName -eq "manager.username3"}

    if ($manager) {
        Set-ADUser -Identity $login -Manager $manager.DistinguishedName
        Write-Host "Руководитель назначен: $($manager.Name)" -ForegroundColor Green
    } else {
        Write-Host "Руководитель с указанным именем пользователя не найден." -ForegroundColor Yellow
    }
    
    Write-Host "Пользователь $login успешно создан!" -ForegroundColor Green
} else {
    Write-Host "Ошибка при создании пользователя." -ForegroundColor Red
}
