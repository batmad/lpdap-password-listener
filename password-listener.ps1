# ==============================
# CONFIG
# ==============================
$ApiUrl = "" # API Url
$ApiKey = "" # API Key 
$DCName = $env:COMPUTERNAME
$StateFile = "C:\ldap-listener\last_record_id.txt"

Write-Host "Password Listener Started on $DCName..."

# ==============================
# LOAD LAST RECORD ID
# ==============================
if (Test-Path $StateFile) {
    $lastRecordId = [int64](Get-Content $StateFile)
} else {
    $lastRecordId = 0
}

# ==============================
# MAIN LOOP (Polling 5 detik)
# ==============================
while ($true) {

    try {

        $events = Get-WinEvent -FilterHashtable @{
            LogName='Security'
            Id=4723,4724
        } -MaxEvents 50

        foreach ($event in $events | Sort-Object RecordId) {

            if ($event.RecordId -le $lastRecordId) {
                continue
            }

            $lastRecordId = $event.RecordId

            $xml = [xml]$event.ToXml()

            $targetUser = $xml.Event.EventData.Data |
                Where-Object { $_.Name -eq "TargetUserName" } |
                Select-Object -ExpandProperty '#text'

            $subjectUser = $xml.Event.EventData.Data |
                Where-Object { $_.Name -eq "SubjectUserName" } |
                Select-Object -ExpandProperty '#text'

            $payload = @{
                event_id        = $event.Id
                event_record_id = $event.RecordId
                target_user     = $targetUser
                changed_by      = $subjectUser
                dc_name         = $DCName
                event_time      = $event.TimeCreated
            } | ConvertTo-Json -Depth 5

            Invoke-RestMethod -Uri $ApiUrl `
                -Method POST `
                -Headers @{ "Authorization" = "Bearer $ApiKey" } `
                -ContentType "application/json" `
                -Body $payload

            # Save last processed RecordId
            $lastRecordId | Out-File $StateFile -Force

            Write-Host "Event Sent: $($event.Id) - $targetUser"

        }

    } catch {
        Write-Host "Error: $_"
    }

    Start-Sleep -Seconds 5
}
