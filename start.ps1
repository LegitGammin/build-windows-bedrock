@'
$ErrorActionPreference = "Stop"

$dataRoot   = "C:\data"
$zipPath    = Join-Path $dataRoot "bedrock-server.zip"
$serverDir  = Join-Path $dataRoot "server"
$exePath    = Join-Path $serverDir "bedrock_server.exe"
$propsPath  = Join-Path $serverDir "server.properties"

New-Item -ItemType Directory -Force $dataRoot  | Out-Null
New-Item -ItemType Directory -Force $serverDir | Out-Null

function Set-Prop([string]$key, [string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return }
  if (!(Test-Path $propsPath)) { New-Item -ItemType File -Force $propsPath | Out-Null }

  $content = Get-Content $propsPath -ErrorAction SilentlyContinue
  $pattern = "^\s*{0}\s*=" -f [regex]::Escape($key)

  if ($content -match $pattern) {
    $content = $content | ForEach-Object {
      if ($_ -match $pattern) { "$key=$value" } else { $_ }
    }
  } else {
    $content += "$key=$value"
  }

  Set-Content -Path $propsPath -Value $content -Encoding ASCII
}

# Unpack server if not present
if (!(Test-Path $exePath)) {
  if (!(Test-Path $zipPath)) {
    Write-Host "Missing: $zipPath"
    Write-Host "Place the official Bedrock Dedicated Server (Windows) ZIP at:"
    Write-Host "  C:\data\bedrock-server.zip  (this is your mounted serverfiles folder in GSA)"
    exit 1
  }

  Write-Host "Unpacking Bedrock server from $zipPath to $serverDir ..."
  Expand-Archive -Path $zipPath -DestinationPath $serverDir -Force
}

# Env-driven config (optional)
Set-Prop "server-name"   $env:SERVER_NAME
Set-Prop "max-players"   $env:MAX_PLAYERS
Set-Prop "server-port"   $env:SERVER_PORT
Set-Prop "server-portv6" $env:SERVER_PORT_V6

Write-Host "Starting Bedrock: $exePath"
Set-Location $serverDir
& $exePath
'@ | Set-Content -Encoding UTF8 .\start.ps1
