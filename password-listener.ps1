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
$lastRecordId = if (Test-Path $StateFile) { [int64](Get-Content $StateFile -Raw).Trim() } else { 0 }

# Pre-build headers sekali saja (tidak dibuat ulang tiap iterasi)
$headers = @{ "Authorization" = "Bearer $ApiKey" }

# ==============================
# MAIN LOOP
# ==============================
while ($true) {
    try {
        # Gunakan -FilterXPath untuk filter langsung di level WinEvent (lebih efisien)
        $xpath = "*[System[(EventID=4723 or EventID=4724) and EventRecordID > $lastRecordId]]"
        
        $events = Get-WinEvent -LogName 'Security' -FilterXPath $xpath -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($events) {
            # Sort dan proses
            foreach ($event in ($events | Sort-Object RecordId)) {
                try {
                    $xml = [xml]$event.ToXml()
                    $data = $xml.Event.EventData.Data

                    $targetUser  = ($data | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
                    $subjectUser = ($data | Where-Object { $_.Name -eq "SubjectUserName" }).'#text'

                    # Bebaskan XML object segera setelah dipakai
                    $xml = $null

                    # Skip akun komputer, system, service
                    if ([string]::IsNullOrWhiteSpace($targetUser) -or
                        $targetUser -like '*$' -or
                        $subjectUser -like '*$' -or
                        $targetUser -eq 'SYSTEM') {
                        $lastRecordId = $event.RecordId
                        continue
                    }

                    $payload = [ordered]@{
                        event_id        = $event.Id
                        event_record_id = $event.RecordId
                        target_user     = $targetUser
                        changed_by      = $subjectUser
                        dc_name         = $DCName
                        event_time      = $event.TimeCreated.ToString("o") # ISO 8601
                    } | ConvertTo-Json -Depth 3 -Compress

                    Invoke-RestMethod -Uri $ApiUrl `
                        -Method POST `
                        -Headers $headers `
                        -ContentType "application/json" `
                        -Body $payload | Out-Null

                    $lastRecordId = $event.RecordId
                    $lastRecordId | Out-File $StateFile -Force -NoNewline

                    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Event Sent: $($event.Id) - $targetUser"
                }
                catch {
                    Write-Host "Error processing event $($event.RecordId): $_"
                }
                finally {
                    $xml = $null
                }
            }
        }
    }
    catch {
        Write-Host "Error fetching events: $_"
    }
    finally {
        # Paksa release memory setiap loop
        $events = $null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    Start-Sleep -Seconds 5
}
