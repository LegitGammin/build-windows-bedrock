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

#
