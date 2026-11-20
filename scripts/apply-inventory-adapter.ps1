param(
    [Parameter(Mandatory=$true)][string]$InventoryRoot,
    [string]$PreparedRoot = ''
)
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
if (-not $PreparedRoot) { $PreparedRoot = Join-Path $taskProject 'work/inventory-integration' }
$taskPrepared = (Resolve-Path -LiteralPath $PreparedRoot).Path
$taskInventory = (Resolve-Path -LiteralPath $InventoryRoot).Path
$taskManifest = Get-Content -LiteralPath (Join-Path $taskPrepared 'apply-manifest.json') -Raw | ConvertFrom-Json
if ($taskInventory -ne (Resolve-Path -LiteralPath $taskManifest.source).Path) { throw 'Prepared inventory source does not match the target.' }
$taskFiles = @('server.js','public/index.html')
foreach ($taskRelative in $taskFiles) {
    $taskTarget = [IO.Path]::GetFullPath((Join-Path $taskInventory $taskRelative))
    if (-not $taskTarget.StartsWith($taskInventory + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Target escapes the inventory directory.' }
    if ((Get-FileHash -LiteralPath $taskTarget -Algorithm SHA256).Hash -ne $taskManifest.files.$taskRelative) { throw "Inventory source changed since preparation: $taskRelative" }
}
$taskModule = Join-Path $taskInventory 'pos-deliveries.cjs'
if (Test-Path -LiteralPath $taskModule) { throw 'Inventory connector already exists. Review it before replacing it.' }
$taskBackup = Join-Path $taskProject ('data/inventory-source-backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path (Join-Path $taskBackup 'public') -Force | Out-Null
foreach ($taskRelative in $taskFiles) {
    Copy-Item -LiteralPath (Join-Path $taskInventory $taskRelative) -Destination (Join-Path $taskBackup $taskRelative)
}
try {
    foreach ($taskRelative in $taskFiles) {
        Copy-Item -LiteralPath (Join-Path $taskPrepared $taskRelative) -Destination (Join-Path $taskInventory $taskRelative) -Force
    }
    Copy-Item -LiteralPath (Join-Path $taskPrepared 'pos-deliveries.cjs') -Destination $taskModule
} catch {
    foreach ($taskRelative in $taskFiles) {
        Copy-Item -LiteralPath (Join-Path $taskBackup $taskRelative) -Destination (Join-Path $taskInventory $taskRelative) -Force
    }
    throw
}
Write-Output 'Inventory connector applied to server.js, public/index.html and pos-deliveries.cjs. Inventory data.json and existing working changes were not modified.'
Write-Output "Source backup: $taskBackup"
