$ErrorActionPreference = "Stop"

# ---- Paths ----
$dataRoot   = "C:\data"
$serverDir  = Join-Path $dataRoot "server"
$exePath    = Join-Path $serverDir "bedrock_server.exe"
$propsPath  = Join-Path $serverDir "server.properties"

New-Item -ItemType Directory -Force $dataRoot  | Out-Null
New-Item -ItemType Directory -Force $serverDir | Out-Null

function Set-Prop([string]$key, [string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return }

  if (!(Test-Path $propsPath)) {
    New-Item -ItemType File -Force $propsPath | Out-Null
  }

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

function Get-LatestBdsUrl {
  # Optional override (recommended fallback)
  if ($env:DIRECT_DOWNLOAD_URL) { return $env:DIRECT_DOWNLOAD_URL }

  # Ensure TLS 1.2 for older PowerShell
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  $page = "https://www.minecraft.net/en-us/download/server/bedrock"
  $html = (Invoke-WebRequest -Uri $page -UseBasicParsing).Content

  # Try to find a Windows BDS zip link in the page HTML (patterns cover common variants)
  $patterns = @(
    'https?://minecraft\.azureedge\.net/bin-win/bedrock-server-[0-9\.]+\.zip',
    'https?://minecraft\.azureedge\.net/[^"]*bin-win/bedrock-server-[^"]+\.zip',
    'https?://www\.minecraft\.net/bedrockdedicatedserver/bin-win/bedrock-server-[^"]+\.zip'
  )

  foreach ($p in $patterns) {
    $m = [regex]::Match($html, $p, "IgnoreCase")
    if ($m.Success) { return $m.Value }
  }

  throw "Could not detect the Bedrock server download URL. Set DIRECT_DOWNLOAD_URL env var."
}

# ---- Install server if missing ----
if (!(Test-Path $exePath)) {
  Write-Host "Bedrock server not found at $exePath. Downloading latest..."

  $url = Get-LatestBdsUrl
  Write-Host "Download URL: $url"

  $dlDir = Join-Path $dataRoot "downloads"
  New-Item -ItemType Directory -Force $dlDir | Out-Null

  $zipPath = Join-Path $dlDir "bedrock-server.zip"

  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
  Write-Host "Downloaded to: $zipPath"

  Write-Host "Unpacking to: $serverDir"
  Expand-Archive -Path $zipPath -DestinationPath $serverDir -Force
}

# ---- Optional env-driven config ----
Set-Prop "server-name"   $env:SERVER_NAME
Set-Prop "max-players"   $env:MAX_PLAYERS
Set-Prop "server-port"   $env:SERVER_PORT
Set-Prop "server-portv6" $env:SERVER_PORT_V6

Write-Host "Starting Bedrock: $exePath"
Set-Location $serverDir
& $exePath
