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

# If server exe missing, unpack from ZIP in mounted data folder
if (!(Test-Path $exePath)) {
  if (!(Test-Path $zipPath)) {
    Write-Host "Missing: $zipPath"
    Write-Host "Download the official Bedrock Dedicated Server (Windows) ZIP and place it at:"
    Write-Host "  C:\data\bedrock-server.zip  (this is your mounted /serverfiles folder in GSA)"
    exit 1
  }

  Write-Host "Unpacking Bedrock server from $zipPath to $serverDir ..."
  Expand-Archive -Path $zipPath -DestinationPath $serverDir -Force
}

# Optional env-driven config
Set-Prop "server-name"        $env:SERVER_NAME
Set-Prop "max-players"        $env:MAX_PLAYERS
Set-Prop "server-port"        $env:SERVER_PORT
Set-Prop "server-portv6"      $env:SERVER_PORT_V6
Set-Prop "gamemode"           $env:GAMEMODE
Set-Prop "difficulty"         $env:DIFFICULTY
Set-Prop "level-name"         $env:LEVEL_NAME
Set-Prop "online-mode"        $env:ONLINE_MODE
Set-Prop "allow-cheats"       $env:ALLOW_CHEATS

Write-Host "Starting Bedrock: $exePath"
Set-Location $serverDir
& $exePath
