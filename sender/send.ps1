param([Parameter(Mandatory=$true)][string]$File)
$ProgressPreference = 'SilentlyContinue'
$cfg = @{}
Get-Content (Join-Path $PSScriptRoot 'sender.cfg') | ForEach-Object { if ($_ -match '^\s*(\w+)\s*=\s*(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() } }
if (-not $cfg.token -or $cfg.token -match 'PASTE') { Write-Host 'Put your GitHub token in sender\sender.cfg first (see README).' -ForegroundColor Red; exit 1 }
if (-not (Test-Path $File)) { Write-Host "File not found: $File" -ForegroundColor Red; exit 1 }
$ext = [IO.Path]::GetExtension($File).ToLower()
if ($ext -notin '.mp3','.mp4') { Write-Host 'Only .mp3 and .mp4 files.' -ForegroundColor Red; exit 1 }
$sizeMB = (Get-Item $File).Length / 1MB
if ($sizeMB -gt 50) { Write-Host ("That file is {0:N0} MB. GitHub mode allows 50 MB - shrink it first." -f $sizeMB) -ForegroundColor Red; exit 1 }
$caption = Read-Host 'Caption to show on screen (press Enter to skip)'
$repo = $cfg.repo; $br = if ($cfg.branch) { $cfg.branch } else { 'main' }
$h = @{ Authorization = "Bearer $($cfg.token)"; 'User-Agent' = 'nova6-sender'; Accept = 'application/vnd.github+json' }
$id = [guid]::NewGuid().ToString('N').Substring(0,10)
$fname = "$id$ext"
try {
  Write-Host ("Transmitting {0} ({1:N1} MB) ..." -f [IO.Path]::GetFileName($File), $sizeMB)
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($File))
  $body = @{ message = "transmission $id"; content = $b64; branch = $br } | ConvertTo-Json
  Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/media/$fname" -Method Put -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 3600 | Out-Null
  for ($try = 0; $try -lt 5; $try++) {                      # add to manifest (retry if two sends collide)
    $m = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/manifest.json?ref=$br" -Headers $h
    $cur = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.content -replace '\s',''))) | ConvertFrom-Json
    $items = @(); if ($cur.items) { $items = @($cur.items) }
    $type = if ($ext -eq '.mp4') { 'video' } else { 'audio' }
    $items += [pscustomobject]@{ id = $id; file = $fname; type = $type; caption = $caption; ts = [int][double]::Parse((Get-Date -UFormat %s)) }
    if ($items.Count -gt 40) { $items = $items[-40..-1] }
    $json = (@{ items = $items } | ConvertTo-Json -Depth 5)
    $put = @{ message = "manifest $id"; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)); sha = $m.sha; branch = $br } | ConvertTo-Json
    try { Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/manifest.json" -Method Put -Headers $h -Body $put -ContentType 'application/json' | Out-Null; break }
    catch { if ($try -eq 4) { throw } ; Start-Sleep -Seconds 1 }
  }
  Write-Host 'TRANSMISSION SENT. Open screens pick it up within ~15-30 seconds.' -ForegroundColor Cyan
} catch {
  $msg = $_.Exception.Message
  if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
  Write-Host "FAILED: $msg" -ForegroundColor Red
}
