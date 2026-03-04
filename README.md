# LDAP Password Change Listener

Script PowerShell ini digunakan untuk memonitor event perubahan password pada **Active Directory Domain Controller** dan mengirimkannya ke API eksternal melalui HTTP POST.

Script akan membaca Event ID:

* **4723** → User changed password
* **4724** → User reset password

Event dikirim ke endpoint API dalam format JSON.

---

## 1. Fitur

* Monitoring Event Log Security secara real-time (polling 5 detik)
* Tracking last processed `RecordId`
* Kirim event ke REST API
* Mendukung multiple Domain Controller (DC)
* Menyertakan nama DC pengirim event

---

## 2. Arsitektur

Script dijalankan di setiap:

* Domain Controller (DC)
* Disaster Recovery Controller (DRC) / Secondary DC

Karena event password change hanya tercatat di DC yang memproses request tersebut.

---

## 3. Requirement

* Windows Server (Domain Controller)
* PowerShell 5.1+
* Hak akses membaca Security Event Log (Administrator)
* Audit Policy aktif untuk:

  * Account Management
  * User Account Management

Cek audit policy:

```powershell
auditpol /get /subcategory:"User Account Management"
```

Jika belum aktif:

```powershell
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
```

---

## 4. Konfigurasi

Edit bagian CONFIG pada script:

```powershell
$ApiUrl = "http://10.14.155.34:4567/api/password/ldap/event"
$ApiKey = "YOUR_API_KEY"
$DCName = $env:COMPUTERNAME
$StateFile = "C:\ldap-listener\last_record_id.txt"
```

### Parameter

| Variable     | Keterangan                             |
| ------------ | -------------------------------------- |
| `$ApiUrl`    | Endpoint API tujuan                    |
| `$ApiKey`    | Bearer token untuk autentikasi         |
| `$DCName`    | Nama Domain Controller (otomatis)      |
| `$StateFile` | File untuk menyimpan RecordId terakhir |

---

## 5. Payload yang Dikirim ke API

Contoh JSON:

```json
{
  "event_id": 4723,
  "event_record_id": 123456,
  "target_user": "jdoe",
  "changed_by": "administrator",
  "dc_name": "DC01",
  "event_time": "2026-03-04T08:12:44"
}
```

---

## 6. Cara Menjalankan

### Manual

```powershell
powershell -ExecutionPolicy Bypass -File ldap-listener.ps1
```

### Sebagai Scheduled Task (Recommended)

1. Buka Task Scheduler
2. Create Task
3. Run with highest privileges
4. Trigger:

   * At startup
5. Action:

   * Start a Program
   * Program: `powershell.exe`
   * Arguments:

     ```
     -ExecutionPolicy Bypass -File "C:\ldap-listener\ldap-listener.ps1"
     ```

---

## 7. Cara Kerja Script

1. Load `last_record_id.txt`
2. Ambil event Security (4723 & 4724)
3. Filter berdasarkan RecordId terbaru
4. Kirim event ke API
5. Simpan RecordId terakhir
6. Sleep 5 detik
7. Ulangi

---

## 8. Best Practice Deployment

Disarankan:

* Install di semua Domain Controller (DC & DRC)
* Jangan share file `last_record_id.txt` antar server
* Di sisi API buat unique constraint:

```
event_record_id + dc_name
```

Karena RecordId hanya unik per DC.

---

## 9. Troubleshooting

### Script tidak mengirim event

* Pastikan Audit Policy aktif
* Pastikan service account bisa baca Security log
* Test manual:

```powershell
Get-WinEvent -LogName Security -MaxEvents 5
```

### API tidak menerima data

Test manual:

```powershell
Invoke-RestMethod -Uri $ApiUrl -Method GET
```

Pastikan:

* API hidup
* Port terbuka
* Firewall tidak blocking

---

## 10. Security Notes

* Simpan API Key dengan aman
* Batasi akses endpoint API hanya dari IP Domain Controller
* Gunakan HTTPS jika memungkinkan

---

## 11. Stop Script

Tekan:

```
CTRL + C
```

Jika dijalankan via Scheduled Task, hentikan dari Task Scheduler.

---
