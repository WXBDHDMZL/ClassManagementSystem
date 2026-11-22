param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$DataDir,
    [int]$WaitSeconds = 10
)

$ErrorActionPreference = "Stop"

$exePath = (Resolve-Path $Exe).Path
$sourceDir = (Resolve-Path $DataDir).Path
if (-not (Test-Path (Join-Path $sourceDir "class_management_data.enc"))) {
    throw "DataDir must contain class_management_data.enc"
}

$tempDir = Join-Path $env:TEMP ("cms_smoke_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
Copy-Item -Path (Join-Path $sourceDir "*") -Destination $tempDir -Recurse -Force

$oldDataDir = $env:CMS_DATA_DIR
$oldTarget = $env:CMS_STARTUP_TARGET
$process = $null
try {
    $env:CMS_DATA_DIR = $tempDir
    $env:CMS_STARTUP_TARGET = "tray"
    $process = Start-Process -FilePath $exePath -PassThru
    Start-Sleep -Seconds $WaitSeconds
    if ($process.HasExited) {
        throw "Application exited during smoke test (code $($process.ExitCode))"
    }
    Write-Output "SMOKE_OK pid=$($process.Id) data=$tempDir"
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    if ($null -eq $oldDataDir) { Remove-Item Env:CMS_DATA_DIR -ErrorAction SilentlyContinue } else { $env:CMS_DATA_DIR = $oldDataDir }
    if ($null -eq $oldTarget) { Remove-Item Env:CMS_STARTUP_TARGET -ErrorAction SilentlyContinue } else { $env:CMS_STARTUP_TARGET = $oldTarget }
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
