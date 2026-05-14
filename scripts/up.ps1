<#
.SYNOPSIS
    一键启动 monitoring-stack 全部服务
#>

$ErrorActionPreference = "Stop"
$projectDir = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($PSScriptRoot, "..")
)

Write-Host "=== Starting monitoring-stack ===" -ForegroundColor Cyan
Write-Host "Project: $projectDir"

Set-Location $projectDir

docker compose up -d --build

Write-Host ""
Write-Host "Waiting for services to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$services = @(
    @{ Name = "Prometheus";    Url = "http://localhost:8080/prometheus/" }
    @{ Name = "Grafana";       Url = "http://localhost:8080/grafana/" }
    @{ Name = "Alertmanager";  Url = "http://localhost:8080/alertmanager/" }
    @{ Name = "Alert Receiver"; Url = "http://localhost:8080/alert-receiver/" }
    @{ Name = "Flask App";     Url = "http://localhost:8080/flask/" }
)

Write-Host ""
Write-Host "=== Service Status ===" -ForegroundColor Cyan

foreach ($svc in $services) {
    try {
        $response = Invoke-WebRequest -Uri $svc.Url -Method HEAD -UseBasicParsing `
            -Credential (New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "monitoring2025" -AsPlainText -Force))) `
            -ErrorAction SilentlyContinue
        $status = "OK ($($response.StatusCode))"
    }
    catch {
        $status = "Needs auth or starting..."
    }
    Write-Host "  $($svc.Name): $($svc.Url) - $status"
}

Write-Host ""
Write-Host "=== All services started ===" -ForegroundColor Green
Write-Host "Nginx gateway: http://localhost:8080" -ForegroundColor White
Write-Host "  /prometheus/   - Prometheus UI (auth required)" -ForegroundColor Gray
Write-Host "  /grafana/      - Grafana Dashboards (auth required)" -ForegroundColor Gray
Write-Host "  /alertmanager/ - Alertmanager UI (auth required)" -ForegroundColor Gray
Write-Host "  /alert-receiver/ - Alert webhook log (auth required)" -ForegroundColor Gray
Write-Host "  /flask/        - Flask app (no auth)" -ForegroundColor Gray
Write-Host "Auth: admin / monitoring2025" -ForegroundColor Yellow
