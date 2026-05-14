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
    @{ Name = "Prometheus";    Url = "http://localhost:9090/-/healthy" }
    @{ Name = "Grafana";       Url = "http://localhost:3000/api/health" }
    @{ Name = "Alertmanager";  Url = "http://localhost:9093/-/healthy" }
    @{ Name = "Flask App";     Url = "http://localhost:8000/" }
    @{ Name = "Alert Receiver"; Url = "http://localhost:5001/" }
    @{ Name = "cAdvisor";      Url = "http://localhost:8080/containers/" }
    @{ Name = "Node Exporter"; Url = "http://localhost:9100/metrics" }
)

Write-Host ""
Write-Host "=== Service Status ===" -ForegroundColor Cyan

foreach ($svc in $services) {
    try {
        $response = Invoke-WebRequest -Uri $svc.Url -Method HEAD -UseBasicParsing -ErrorAction Stop
        $status = "OK ($($response.StatusCode))"
    }
    catch {
        $status = "Starting..."
    }
    Write-Host "  $($svc.Name): $status"
}

Write-Host ""
Write-Host "=== All services started ===" -ForegroundColor Green
Write-Host "  Prometheus:    http://localhost:9090" -ForegroundColor White
Write-Host "  Grafana:       http://localhost:3000  (admin/admin)" -ForegroundColor White
Write-Host "  Alertmanager:  http://localhost:9093" -ForegroundColor White
Write-Host "  Flask App:     http://localhost:8000" -ForegroundColor White
Write-Host "  Alert Receiver:http://localhost:5001" -ForegroundColor White
Write-Host "  cAdvisor:      http://localhost:8080" -ForegroundColor White
Write-Host "  Node Exporter: http://localhost:9100/metrics" -ForegroundColor White
