$ErrorActionPreference = "Stop"

# ---------------- Paths ----------------
$dataRoot   = "C:\data"
$serverDir  = Join-Path $dataRoot "server"
$exePath    = Join-Path $serverDir "bedrock_server.exe"
$propsPath  = Join-Path $serverDir "server.properties"
$verFile    = Join-Path $serverDir ".bds_version"
$urlFile    = Join-Path $serverDir ".bds_url"

New-Item -ItemType Directory -Force $dataRoot  | Out-Null
New-Item -ItemType Directory -Force $serverDir | Out-Null

# ---------------- Options (env) ----------------
# AUTO_UPDATE: "true"/"false" (default true)
# FORCE_UPDATE: "true" forces install even if same version
# DIRECT_DOWNLOAD_URL: optional override to a specific zip
function Is-True($v) {
  if ($null -eq $v) { return $false }
  return @("1","true","yes","y","on") -contains ($v.ToString().ToLower())
}
$AUTO_UPDATE  = if ($env:AUTO_UPDATE) { Is-True $env:AUTO_UPDATE } else { $true }
$FORCE_UPDATE = Is-True $env:FORCE_UPDATE

# ---------------- Helpers ----------------
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

function Parse-VersionFromUrl([string]$url) {
  # bedrock-server-1.20.80.05.zip
  $m = [regex]::Match($url, "bedrock-server-([0-9]+(\.[0-9]+){1,5})\.zip", "IgnoreCase")
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Compare-Version([string]$a, [string]$b) {
  # returns: -1 if a<b, 0 if equal, 1 if a>b
  if ($null -eq $a -or $null -eq $b) { return 0 }
  $pa = $a.Split(".") | ForEach-Object { [int]$_ }
  $pb = $b.Split(".") | ForEach-Object { [int]$_ }
  $len = [Math]::Max($pa.Length, $pb.Length)
  for ($i=0; $i -lt $len; $i++) {
    $va = if ($i -lt $pa.Length) { $pa[$i] } else { 0 }
    $vb = if ($i -lt $pb.Length) { $pb[$i] } else { 0 }
    if ($va -lt $vb) { return -1 }
    if ($va -gt $vb) { return 1 }
  }
  return 0
}

function Get-LatestBdsUrl {
  if ($env:DIRECT_DOWNLOAD_URL) { return $env:DIRECT_DOWNLOAD_URL }

  # TLS 1.2 for older PS
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  $page = "https://www.minecraft.net/en-us/download/server/bedrock"
  $html = (Invoke-WebRequest -Uri $page -UseBasicParsing).Content

  $patterns = @(
    'https?://minecraft\.azureedge\.net/bin-win/bedrock-server-[0-9\.]+\.zip',
    'https?://minecraft\.azureedge\.net/[^"]*bin-win/bedrock-server-[^"]+\.zip',
    'https?://www\.minecraft\.net/bedrockdedicatedserver/bin-win/bedrock-server-[^"]+\.zip'
  )

  foreach ($p in $patterns) {
    $m = [regex]::Match($html, $p, "IgnoreCase")
    if ($m.Success) { return $m.Value }
  }

  throw "Could not detect Bedrock download URL. Set DIRECT_DOWNLOAD_URL."
}

function Install-Or-UpdateBedrock {
  $latestUrl = Get-LatestBdsUrl
  $latestVer = Parse-VersionFromUrl $latestUrl

  $installedVer = if (Test-Path $verFile) { (Get-Content $verFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim() } else { $null }
  $installedUrl = if (Test-Path $urlFile) { (Get-Content $urlFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim() } else { $null }

  $needInstall = !(Test-Path $exePath)
  $needUpdate  = $false

  if ($needInstall) {
    $needUpdate = $true
    Write-Host "Bedrock not installed yet. Will install."
  } elseif ($AUTO_UPDATE) {
    if ($FORCE_UPDATE) {
      $needUpdate = $true
      Write-Host "FORCE_UPDATE enabled. Will update/reinstall."
    } else {
      if ($latestVer -and $installedVer) {
        $cmp = Compare-Version $installedVer $latestVer
        if ($cmp -lt 0) { $needUpdate = $true }
      } else {
        # If we can't parse versions, fall back to URL change detection
        if ($latestUrl -ne $installedUrl) { $needUpdate = $true }
      }
    }
  }

  if (-not $needUpdate) {
    Write-Host "No update needed. Installed version: $installedVer"
    return
  }

  Write-Host "Latest URL: $latestUrl"
  if ($latestVer) { Write-Host "Latest version: $latestVer" }

  $dlDir  = Join-Path $dataRoot "downloads"
  $tmpDir = Join-Path $dataRoot "tmp_extract"
  New-Item -ItemType Directory -Force $dlDir | Out-Null

  if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Force $tmpDir | Out-Null

  $zipPath = Join-Path $dlDir "bedrock-server.zip"
  Write-Host "Downloading..."
  Invoke-WebRequest -Uri $latestUrl -OutFile $zipPath -UseBasicParsing

  Write-Host "Extracting..."
  Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force

  # Preserve these from existing install
  $preserve = @(
    "worlds",
    "server.properties",
    "allowlist.json",
    "permissions.json",
    ".bds_version",
    ".bds_url"
  )

  # Copy new files over, excluding preserved items
  Write-Host "Updating server files (preserving worlds + configs)..."
  Get-ChildItem -Path $tmpDir -Force | ForEach-Object {
    $name = $_.Name
    if ($preserve -contains $name) {
      return
    }
    $dest = Join-Path $serverDir $name
    if ($_.PSIsContainer) {
      Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
    } else {
      Copy-Item -Path $_.FullName -Destination $dest -Force
    }
  }

  # Record installed version/url
  if ($latestVer) { Set-Content -Path $verFile -Value $latestVer -Encoding ASCII }
  Set-Content -Path $urlFile -Value $latestUrl -Encoding ASCII

  Write-Host "Update complete."
}

# ---------------- Install/Update before start ----------------
Install-Or-UpdateBedrock

# ---------------- Apply env config (optional) ----------------
Set-Prop "server-name"   $env:SERVER_NAME
Set-Prop "max-players"   $env:MAX_PLAYERS
Set-Prop "server-port"   $env:SERVER_PORT
Set-Prop "server-portv6" $env:SERVER_PORT_V6

Write-Host "Starting Bedrock: $exePath"
Set-Location $serverDir
& $exePath
