$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------- Paths ----------------
$dataRoot   = "C:\data"
$serverDir  = Join-Path $dataRoot "server"
$exePath    = Join-Path $serverDir "bedrock_server.exe"
$propsPath  = Join-Path $serverDir "server.properties"
$verFile    = Join-Path $serverDir ".bds_version"
$urlFile    = Join-Path $serverDir ".bds_url"
$logDir     = Join-Path $dataRoot "logs"
$logFile    = Join-Path $logDir "bedrock.log"

New-Item -ItemType Directory -Force $dataRoot  | Out-Null
New-Item -ItemType Directory -Force $serverDir | Out-Null
New-Item -ItemType Directory -Force $logDir    | Out-Null

# ---------------- Options (env) ----------------
function Is-True($v) {
  if ($null -eq $v) { return $false }
  return @("1","true","yes","y","on") -contains ($v.ToString().ToLower())
}

# AUTO_UPDATE: default true
$AUTO_UPDATE  = if ($env:AUTO_UPDATE) { Is-True $env:AUTO_UPDATE } else { $true }
# FORCE_UPDATE: default false
$FORCE_UPDATE = Is-True $env:FORCE_UPDATE
# BDS_CHANNEL: "release" (default) or "preview"
$BDS_CHANNEL  = if ($env:BDS_CHANNEL -and $env:BDS_CHANNEL.Trim().Length -gt 0) { $env:BDS_CHANNEL.Trim().ToLower() } else { "release" }
if ($BDS_CHANNEL -ne "release" -and $BDS_CHANNEL -ne "preview") { $BDS_CHANNEL = "release" }

# LOG_TO_FILE: default true
$LOG_TO_FILE = if ($env:LOG_TO_FILE) { Is-True $env:LOG_TO_FILE } else { $true }

# ---------------- Helpers ----------------
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

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
  $m = [regex]::Match($url, "bedrock-server-([0-9]+(\.[0-9]+){1,5})\.zip", "IgnoreCase")
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Compare-Version([string]$a, [string]$b) {
  # returns: -1 if a<b, 0 if equal, 1 if a>b
  if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { return 0 }

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

function Invoke-WebRequest-Retry([string]$uri, [string]$outFile = $null, [int]$retries = 3) {
  for ($i=1; $i -le $retries; $i++) {
    try {
      if ($outFile) {
        Invoke-WebRequest -Uri $uri -OutFile $outFile -UseBasicParsing
        return
      } else {
        return Invoke-WebRequest -Uri $uri -UseBasicParsing
      }
    } catch {
      if ($i -eq $retries) { throw }
      Start-Sleep -Seconds (2 * $i)
    }
  }
}

function Get-LatestBdsUrl-And-Version {
  # Override: exact zip URL
  if ($env:DIRECT_DOWNLOAD_URL -and $env:DIRECT_DOWNLOAD_URL.Trim().Length -gt 0) {
    $u = $env:DIRECT_DOWNLOAD_URL.Trim()
    $v = Parse-VersionFromUrl $u
    return @{ url = $u; version = $v; channel = "override" }
  }

  # Use bedrock-server-data metadata (release/preview)
  $versionsUrl = "https://raw.githubusercontent.com/EndstoneMC/bedrock-server-data/v2/versions.json"
  $versionsResp = Invoke-WebRequest-Retry -uri $versionsUrl
  $versions = $versionsResp.Content | ConvertFrom-Json

  $latest = $versions.$BDS_CHANNEL.latest
  if (-not $latest) {
    throw "Could not read latest version for channel '$BDS_CHANNEL' from versions.json"
  }

  $metaPath = if ($BDS_CHANNEL -eq "release") { "release/$latest/metadata.json" } else { "preview/$latest/metadata.json" }
  $metaUrl  = "https://raw.githubusercontent.com/EndstoneMC/bedrock-server-data/v2/$metaPath"
  $metaResp = Invoke-WebRequest-Retry -uri $metaUrl
  $meta = $metaResp.Content | ConvertFrom-Json

  $winUrl = $meta.binary.windows.url
  if (-not $winUrl) { throw "Could not read windows.url from metadata.json" }

  # Prefer metadata version if present, else parse from URL
  $ver = $meta.version
  if (-not $ver) { $ver = Parse-VersionFromUrl $winUrl }

  return @{ url = $winUrl; version = $ver; channel = $BDS_CHANNEL }
}

function Install-Or-UpdateBedrock {
  $installedVer = if (Test-Path $verFile) { (Get-Content $verFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim() } else { $null }
  $installedUrl = if (Test-Path $urlFile) { (Get-Content $urlFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim() } else { $null }

  $needInstall = !(Test-Path $exePath)

  $latest = Get-LatestBdsUrl-And-Version
  $latestUrl = $latest.url
  $latestVer = $latest.version

  $needUpdate = $false

  if ($needInstall) {
    Write-Host "Bedrock not installed yet. Will install."
    $needUpdate = $true
  } elseif ($AUTO_UPDATE) {
    if ($FORCE_UPDATE) {
      Write-Host "FORCE_UPDATE enabled. Will reinstall/update."
      $needUpdate = $true
    } elseif ($latestVer -and $installedVer) {
      $cmp = Compare-Version $installedVer $latestVer
      if ($cmp -lt 0) { $needUpdate = $true }
    } else {
      # If we can't compare versions, fall back to URL change
      if ($installedUrl -ne $latestUrl) { $needUpdate = $true }
    }
  }

  Write-Host "Latest channel: $($latest.channel)"
  Write-Host "Latest URL: $latestUrl"
  if ($latestVer) { Write-Host "Latest version: $latestVer" }
  if ($installedVer) { Write-Host "Installed version: $installedVer" }

  if (-not $needUpdate) {
    Write-Host "No update needed."
    return
  }

  $dlDir  = Join-Path $dataRoot "downloads"
  $tmpDir = Join-Path $dataRoot "tmp_extract"

  New-Item -ItemType Directory -Force $dlDir | Out-Null
  if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Force $tmpDir | Out-Null

  $zipPath = Join-Path $dlDir "bedrock-server.zip"

  Write-Host "Downloading Bedrock server ZIP..."
  Invoke-WebRequest-Retry -uri $latestUrl -outFile $zipPath -retries 4

  Write-Host "Extracting ZIP..."
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

  Write-Host "Updating server files (preserving worlds + configs)..."
  Get-ChildItem -Path $tmpDir -Force | ForEach-Object {
    $name = $_.Name
    if ($preserve -contains $name) { return }

    $dest = Join-Path $serverDir $name
    if ($_.PSIsContainer) {
      Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
    } else {
      Copy-Item -Path $_.FullName -Destination $dest -Force
    }
  }

  if ($latestVer) { Set-Content -Path $verFile -Value $latestVer -Encoding ASCII }
  Set-Content -Path $urlFile -Value $latestUrl -Encoding ASCII

  Write-Host "Install/Update complete."
}

# ---------------- Install / Update ----------------
Install-Or-UpdateBedrock

# ---------------- Apply env config (optional) ----------------
Set-Prop "server-name"   $env:SERVER_NAME
Set-Prop "max-players"   $env:MAX_PLAYERS
Set-Prop "server-port"   $env:SERVER_PORT
Set-Prop "server-portv6" $env:SERVER_PORT_V6

# ---------------- Start server ----------------
Write-Host "Starting Bedrock: $exePath"
Set-Location $serverDir

if ($LOG_TO_FILE) {
  Write-Host "Logging to: $logFile"
  # Tee stdout/stderr to a file and still show in console
  & $exePath 2>&1 | Tee-Object -FilePath $logFile -Append
} else {
  & $exePath
}
