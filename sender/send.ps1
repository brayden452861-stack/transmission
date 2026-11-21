param([Parameter(Mandatory=$true)][string]$File)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}   # older Windows PowerShell defaults to TLS 1.0, which GitHub refuses
$log = Join-Path $PSScriptRoot 'last_error.txt'
try {
  $cfgPath = Join-Path $PSScriptRoot 'sender.cfg'
  if (-not (Test-Path $cfgPath)) { throw "sender.cfg not found. It must sit in the same folder as send.bat." }
  $cfg = @{}
  Get-Content $cfgPath | ForEach-Object { if ($_ -match '^\s*(\w+)\s*=\s*(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() } }
  if (-not $cfg.token -or $cfg.token -match 'PASTE') { throw "Put your GitHub token in sender.cfg (token=...)." }
  $File = (Resolve-Path -LiteralPath $File).Path
  $ext = [IO.Path]::GetExtension($File).ToLower()
  if ($ext -ne '.mp3' -and $ext -ne '.mp4') { throw "Only .mp3 and .mp4 files (got '$ext')." }
  $len = (Get-Item -LiteralPath $File).Length
  $sizeMB = $len / 1MB
  if ($sizeMB -gt 50) { throw ("That file is {0:N0} MB. GitHub mode allows 50 MB - shrink it first." -f $sizeMB) }
  $caption = Read-Host 'Caption to show on screen (press Enter to skip)'
  $repo = $cfg.repo; $br = if ($cfg.branch) { $cfg.branch } else { 'main' }
  $h = @{ Authorization = "Bearer $($cfg.token)"; 'User-Agent' = 'nova6-sender'; Accept = 'application/vnd.github+json' }
  $id = [guid]::NewGuid().ToString('N').Substring(0,10)
  $fname = "$id$ext"

  Write-Host ("Uploading {0} ({1:N1} MB) to {2} ..." -f [IO.Path]::GetFileName($File), $sizeMB, $repo)
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($File))
  # build the JSON by hand: ConvertTo-Json chokes on very large strings
  $body = '{"message":"transmission ' + $id + '","branch":"' + $br + '","content":"' + $b64 + '"}'
  Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/media/$fname" -Method Put -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 3600 | Out-Null
  $body = $null; $b64 = $null; [GC]::Collect()

  Write-Host 'File uploaded. Adding it to the transmission list ...'
  $type = if ($ext -eq '.mp4') { 'video' } else { 'audio' }
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $capJson = ($caption | ConvertTo-Json -Compress); if (-not $capJson) { $capJson = '""' }
  $newItem = '{"id":"' + $id + '","file":"' + $fname + '","type":"' + $type + '","caption":' + $capJson + ',"ts":' + $ts + '}'
  for ($try = 0; $try -lt 5; $try++) {
    $m = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/manifest.json?ref=$br" -Headers $h
    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.content -replace '\s',''))).TrimStart([char]0xFEFF)
    $old = @()
    try { $parsed = $text | ConvertFrom-Json; if ($parsed.items) { $old = @($parsed.items) } } catch {}
    $parts = @(); foreach ($o in $old) { $parts += ($o | ConvertTo-Json -Compress) }
    $parts += $newItem
    if ($parts.Count -gt 40) { $parts = $parts[($parts.Count-40)..($parts.Count-1)] }
    $json = '{"items":[' + ($parts -join ',') + ']}'
    $put = '{"message":"manifest ' + $id + '","branch":"' + $br + '","sha":"' + $m.sha + '","content":"' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)) + '"}'
    try { Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/manifest.json" -Method Put -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($put)) -ContentType 'application/json' | Out-Null; break }
    catch { if ($try -eq 4) { throw }; Start-Sleep -Seconds 1 }
  }
  if (Test-Path $log) { Remove-Item $log -ErrorAction SilentlyContinue }
  Write-Host 'TRANSMISSION SENT. Open screens pick it up within ~15-30 seconds.' -ForegroundColor Cyan
} catch {
  $msg = $_.Exception.Message
  if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg += "`n" + $_.ErrorDetails.Message }
  Write-Host "FAILED: $msg" -ForegroundColor Red
  try { Set-Content -Path $log -Value $msg } catch {}
}
