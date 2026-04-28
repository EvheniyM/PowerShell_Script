# ============================================
# Script: Export-ADGroupMembersToCSV.ps1
# Description: Экспортирует участников группы Active Directory в CSV файл
# ============================================

param (
    [string]$GroupName = "YOUR-GROUP-NAME",  # Пример: "Windows Virtual Desktop Power Pool Access"
    [string]$GroupDN = "CN=$GroupName,OU=Your-OU,OU=Parent-OU,DC=yourdomain,DC=com",  # Замените на ваш DN
    [string]$OutputFilePath = "C:\Exports\group_members.csv"  # Пример пути для экспорта
)

Import-Module ActiveDirectory

try {
    # Получение всех участников группы (включая вложенные группы)
    $members = Get-ADGroupMember -Identity $GroupDN -Recursive
    
    # Экспорт в CSV
    $members | Select-Object Name, SamAccountName | Export-Csv -Path $OutputFilePath -Encoding UTF8 -NoTypeInformation
    
    # Подсчет и вывод результата
    $memberCount = $members.Count
    Write-Host "Общее количество участников в группе $($GroupName): $memberCount"
    Write-Host "Данные успешно экспортированы в $OutputFilePath"
}
catch {
    Write-Host "Ошибка при получении участников группы: $_" -ForegroundColor Red
}
