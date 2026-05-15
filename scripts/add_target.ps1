<#
.SYNOPSIS
    向 Prometheus file_sd 动态发现配置中追加一个新 target
.DESCRIPTION
    修改 prometheus/file_sd/targets.json，追加一个目标地址。
    自动去重，不会添加已存在的 target。
    Prometheus 会在 refresh_interval (30s) 内自动感知变化，无需重启。
.PARAMETER Target
    要添加的目标地址，格式为 host:port
.EXAMPLE
    .\add_target.ps1 -Target "flask_app:8000"
    .\add_target.ps1 -Target "192.168.1.100:9100"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Target
)

$targetsFile = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($PSScriptRoot, "..", "prometheus", "file_sd", "targets.json")
)

if (-not (Test-Path $targetsFile)) {
    Write-Error "targets.json not found: $targetsFile"
    exit 1
}

$json = Get-Content $targetsFile -Raw | ConvertFrom-Json

# Check if target already exists in any entry
$exists = $false
foreach ($entry in $json) {
    if ($entry.targets -contains $Target) {
        $exists = $true
        break
    }
}

if ($exists) {
    Write-Host "Target '$Target' already exists, skipping."
} else {
    $newEntry = @{
        labels = @{
            job = "flask_app_sd"
            env = "dynamic"
        }
        targets = @($Target)
    }

    $json += $newEntry

    $jsonText = $json | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($targetsFile, $jsonText, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Added target: $Target"
}

Write-Host "Prometheus will auto-detect within 30 seconds (refresh_interval)."
Write-Host "Current targets.json content:"
Get-Content $targetsFile