<#
.SYNOPSIS
    一键停止 monitoring-stack 全部服务
.PARAMETER Clean
    加 -Clean 参数同时删除 volumes（清除所有历史数据）
#>

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$projectDir = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($PSScriptRoot, "..")
)

Write-Host "=== Stopping monitoring-stack ===" -ForegroundColor Cyan
Set-Location $projectDir

if ($Clean) {
    Write-Host "Removing containers and volumes..." -ForegroundColor Yellow
    docker compose down -v
    Write-Host "Volumes removed." -ForegroundColor Yellow
}
else {
    docker compose down
}

Write-Host ""
Write-Host "=== All services stopped ===" -ForegroundColor Green
