# Builds the server and packs it as a Claude Desktop extension:
#   mcp-server\dist\crusam.mcpb
# Share that one file; the other person double-clicks it and clicks Install.
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File mcp-server\tool\package.ps1
# -Version 1.4.0 stamps that version into the extension.
# -NoPack stops after staging build\mcpb\server (bin\server.exe + lib + assets),
# which installer\build_release.ps1 ships inside the app: its "Connect to
# Claude" button sets Claude Desktop up with it (the Microsoft Store build of
# Claude Desktop can't open .mcpb files).
param([string]$Version, [switch]$NoPack)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot          # ...\mcp-server
Set-Location $root

dart pub get | Out-Null
dart test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed; not packaging.' }

dart build cli
if ($LASTEXITCODE -ne 0) { throw 'dart build cli failed.' }

$stage = Join-Path $root 'build\mcpb'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage 'server') | Out-Null
Copy-Item (Join-Path $root 'extension\manifest.json') $stage
if ($Version) {
  $mf = Join-Path $stage 'manifest.json'
  $json = Get-Content $mf -Raw
  $json = $json -replace '"version":\s*"[^"]*"', ('"version": "' + $Version + '"')
  [IO.File]::WriteAllText($mf, $json)
}
# Keep the bundle layout (bin\server.exe + lib\sqlite3.dll): the exe finds
# the DLL relative to itself.
Copy-Item -Recurse (Join-Path $root 'build\cli\windows_x64\bundle\*') (Join-Path $stage 'server')
# Fonts and images for PDF exports (found by walking up from server.exe).
$assets = Join-Path (Split-Path -Parent $root) 'crusam\assets'
foreach ($rel in 'fonts\NotoSans-Regular.ttf', 'fonts\NotoSans-Bold.ttf',
                 'images\aarti_logo.png', 'images\aarti_signature.png', 'images\letterhead.png') {
  $dest = Join-Path $stage "server\assets\$rel"
  New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
  Copy-Item (Join-Path $assets $rel) $dest
}

if ($NoPack) {
  Write-Host "`nStaged server in $(Join-Path $stage 'server')"
  exit 0
}

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$out = Join-Path $dist 'crusam.mcpb'
npx -y @anthropic-ai/mcpb validate (Join-Path $stage 'manifest.json')
if ($LASTEXITCODE -ne 0) { throw 'Manifest validation failed.' }
npx -y @anthropic-ai/mcpb pack $stage $out
if ($LASTEXITCODE -ne 0) { throw 'mcpb pack failed.' }
Copy-Item (Join-Path $root 'extension\INSTALL.md') (Join-Path $dist 'HOW-TO-INSTALL.md') -Force
Write-Host "`nCreated $out"
Write-Host "Send both files in $dist to the other person."
