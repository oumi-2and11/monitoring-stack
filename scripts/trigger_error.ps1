<#
.SYNOPSIS
    循环调用 Flask /error 接口，拉高 5xx 错误率触发告警
#>

$baseUrl = "http://localhost:8000"
$duration = 120
$startTime = Get-Date

Write-Host "Triggering errors for $duration seconds... (Ctrl+C to stop)"
Write-Host "Target: $baseUrl/error"

while (((Get-Date) - $startTime).TotalSeconds -lt $duration) {
    try {
        Invoke-RestMethod -Uri "$baseUrl/error" -Method GET -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # ignore errors
    }

    if ((Get-Random -Maximum 5) -eq 0) {
        try {
            Invoke-RestMethod -Uri "$baseUrl/" -Method GET -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # ignore errors
        }
    }

    Start-Sleep -Milliseconds 200
}

Write-Host "Done. Check Alertmanager and alert_receiver for alerts."
