<#
    Krakenfriends: beta safety net

    The WoW: Forever beta (1.60.x) writes SavedVariables to disk but does not
    load them back when the game starts. Run this BEFORE launching the game:
    it finds your Krakenfriends save and copies it into the addon as
    Restore.lua, which the addon reads at login. Every save it sees is also
    kept in WTF\Krakenfriends-Backups.

    Once the live game loads SavedVariables normally, you don't need this.

    Usage: double-click Restore-Journey.cmd, or
           powershell -ExecutionPolicy Bypass -File Restore-Journey.ps1 [-GameDir <folder>]
#>
param([string]$GameDir)

$ErrorActionPreference = 'Stop'
$addonDir = Split-Path -Parent $PSScriptRoot
if (-not $GameDir) { $GameDir = (Resolve-Path (Join-Path $addonDir '..\..\..')).Path }

$accounts = Join-Path $GameDir 'WTF\Account'
if (-not (Test-Path $accounts)) {
    Write-Host "Couldn't find $accounts"
    Write-Host 'Is the Krakenfriends folder inside <game folder>\Interface\AddOns? You can also pass -GameDir.'
    exit 1
}
$backupDir = Join-Path $GameDir 'WTF\Krakenfriends-Backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Get-Number([string]$text, [string]$key) {
    $m = [regex]::Match($text, '\["' + $key + '"\]\s*=\s*(\d+)')
    if ($m.Success) { return [long]$m.Groups[1].Value }
    return $null
}

# SavedVariables files (account and per-character), the client's .bak copies,
# and our own backups.
$files = @(Get-ChildItem -Path $accounts -Recurse -File |
    Where-Object { $_.Directory.Name -eq 'SavedVariables' -and ($_.Name -eq 'Krakenfriends.lua' -or $_.Name -eq 'Krakenfriends.lua.bak') })
$files += @(Get-ChildItem -Path $backupDir -File -Filter '*.lua')

$candidates = @()
foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    if ($text -notmatch 'Krakenfriends(Char)?DB\s*=\s*\{') { continue }
    $savedAt = Get-Number $text 'savedAt'
    if (-not $savedAt) { continue }
    $created = Get-Number $text 'created'
    if (-not $created) { $created = [long]::MaxValue }
    $candidates += [pscustomobject]@{ File = $file; Text = $text; Created = $created; SavedAt = $savedAt }
}

if ($candidates.Count -eq 0) {
    Write-Host 'No Krakenfriends saves found yet. Play a session first, then run this before the next one.'
    exit 0
}

# Oldest journal first (a session started without a restore begins a new,
# nearly empty one), then its newest save.
$best = $candidates | Sort-Object -Property @{ Expression = { $_.Created }; Ascending = $true }, @{ Expression = { $_.SavedAt }; Descending = $true } | Select-Object -First 1

$epoch = [DateTime]'1970-01-01'
function Get-Stamp([long]$t) { return $epoch.AddSeconds($t).ToLocalTime() }

# Keep a copy of every distinct save, including fresh starts we don't restore.
foreach ($c in $candidates) {
    $suffix = if ($c.Created -eq $best.Created) { '' } else { '-separate' }
    $name = 'Krakenfriends-' + (Get-Stamp $c.SavedAt).ToString('yyyyMMdd-HHmmss') + $suffix + '.lua'
    $target = Join-Path $backupDir $name
    if (-not (Test-Path $target)) { [IO.File]::WriteAllText($target, $c.Text, (New-Object Text.UTF8Encoding $false)) }
}
Get-ChildItem -Path $backupDir -File -Filter '*.lua' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 40 | Remove-Item -Force

$re = [regex]'(?m)^Krakenfriends(?:Char)?DB\s*='
$body = $re.Replace($best.Text, 'KrakenfriendsRestore =', 1)
$header = "-- Restored by tools\Restore-Journey on $(Get-Date -Format 'yyyy-MM-dd HH:mm') from:`r`n-- $($best.File.FullName)`r`n"
[IO.File]::WriteAllText((Join-Path $addonDir 'Restore.lua'), $header + $body, (New-Object Text.UTF8Encoding $false))

$journeys = ([regex]::Matches($best.Text, '\["partnerName"\]')).Count
Write-Host ''
Write-Host "Restored your Krakenfriends journal saved $((Get-Stamp $best.SavedAt).ToString('dd MMM yyyy HH:mm')) ($journeys journey(s))."
$separate = @($candidates | Where-Object { $_.Created -ne $best.Created -and $_.SavedAt -gt $best.SavedAt })
if ($separate.Count -gt 0) {
    Write-Host 'Note: a newer save from a fresh start (a session that began without a restore) was found.'
    Write-Host "      It was kept in $backupDir but not restored, so your longer journal wins."
}
Write-Host 'You can launch the game now.'
