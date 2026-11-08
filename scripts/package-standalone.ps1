$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseFolder = Join-Path $projectRoot ('outputs/release-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+([guid]::NewGuid().ToString('N').Substring(0,6)))
$stage = Join-Path $releaseFolder 'TailorExpress-POS'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($folder in @('server','drizzle')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $stage -Recurse -Force
}
foreach ($folder in @('lib','scripts','public','frontend')) {
    New-Item -ItemType Directory -Path (Join-Path $stage $folder) -Force | Out-Null
}
foreach ($file in @('service.ts','tracking.ts','notifications.ts','storage.ts','domain.ts','domain.test.mjs','catalogue.json')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('lib/'+$file)) -Destination (Join-Path $stage 'lib') -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'public/pos') -Destination (Join-Path $stage 'public') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts/build-flutter.mjs') -Destination (Join-Path $stage 'scripts') -Force
foreach ($folder in @('lib','web','assets','test')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('frontend/'+$folder)) -Destination (Join-Path $stage 'frontend') -Recurse -Force
}
foreach ($file in @('pubspec.yaml','pubspec.lock','analysis_options.yaml')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('frontend/'+$file)) -Destination (Join-Path $stage 'frontend') -Force
}
foreach ($file in @('Start-POS.cmd','Setup-Admin.cmd','.env.example')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $stage -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/LOCAL-SETUP.md') -Destination (Join-Path $stage 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/APP-AND-NOTIFICATIONS.md') -Destination (Join-Path $stage 'APP-AND-NOTIFICATIONS.md') -Force
$package = @{
    name='tailor-express-pos'; version='0.4.0'; private=$true; type='module';
    engines=@{node='>=22.13.0'};
    dependencies=(Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json).dependencies;
    scripts=@{
        start='node --env-file-if-exists=.env --experimental-strip-types server/index.mjs';
        build='node scripts/build-flutter.mjs';
        'setup-admin'='node --env-file-if-exists=.env --experimental-strip-types server/setup-admin.mjs';
        test='node --experimental-strip-types --test server/server.test.mjs server/workflow.test.mjs server/migration.test.mjs server/notifications.test.mjs server/pwa.test.mjs server/branches.test.mjs lib/domain.test.mjs'
    }
}
& node (Join-Path $projectRoot 'scripts/copy-runtime-deps.mjs') $stage
if ($LASTEXITCODE -ne 0) { throw 'Failed to package the runtime dependencies.' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $stage 'package.json'), ($package | ConvertTo-Json -Depth 5), $utf8)
[System.IO.File]::WriteAllText((Join-Path $stage '.gitignore'), "data/`n.env`nnode_modules/`noutputs/`nfrontend/.dart_tool/`nfrontend/build/`n", $utf8)
$archive = Join-Path $projectRoot 'outputs/TailorExpress-POS.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryArchive = Join-Path $projectRoot ('outputs/package-' + [guid]::NewGuid().ToString('N') + '.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $temporaryArchive, [IO.Compression.CompressionLevel]::Optimal, $true)
Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
$resolvedRelease = (Resolve-Path -LiteralPath $releaseFolder).Path
$resolvedOutputs = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'outputs')).Path
if (-not $resolvedRelease.StartsWith($resolvedOutputs + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to remove a package staging directory outside outputs.'
}
# Keep cleanup outside the package staging tree on Windows.
Set-Location -LiteralPath $projectRoot
[Environment]::CurrentDirectory = $projectRoot
for ($attempt = 0; $attempt -lt 4; $attempt++) {
    try {
        Remove-Item -LiteralPath $resolvedRelease -Recurse -Force
        break
    } catch [IO.IOException] {
        if ($attempt -eq 3) { throw }
        Start-Sleep -Milliseconds 250
    }
}
Write-Output "Upload package: $archive"
