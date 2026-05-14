<#
.SYNOPSIS
    循环调用 Flask /slow 接口，模拟高延迟请求
#>

$baseUrl = "http://localhost:8000"
$duration = 120
$startTime = Get-Date

Write-Host "Triggering latency for $duration seconds... (Ctrl+C to stop)"
Write-Host "Target: $baseUrl/slow"

while (((Get-Date) - $startTime).TotalSeconds -lt $duration) {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/slow" -Method GET -ErrorAction SilentlyContinue
        Write-Host "  Response delay: $($response.delay)s"
    }
    catch {
        Write-Host "  Request failed: $_"
    }
}

Write-Host "Done."
