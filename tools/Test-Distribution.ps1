$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File | Sort-Object Name)
if ($files.Count -ne 2) { throw 'Expected exactly two distributable BAT files.' }
$before = @{}
foreach ($file in $files) {
    $before[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw ('BAT must not have a UTF-8 BOM: ' + $file.Name)
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($text -match '(?<!\r)\n') { throw ('BAT must use CRLF: ' + $file.Name) }
    $parts = $text -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2
    if ($parts.Count -ne 2) { throw ('Missing payload: ' + $file.Name) }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($parts[1], [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
    Write-Output ('PASS: encoding, line endings and payload syntax: ' + $file.Name)
}
& (Join-Path $PSScriptRoot 'Build.ps1') | Out-Null
foreach ($file in $files) {
    $after = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if ($before[$file.Name] -ne $after) {
        throw ('Generated BAT differs from committed copy. Run tools/Build.ps1 and commit both source and BAT: ' + $file.Name)
    }
    Write-Output ('PASS: reproducible build: ' + $file.Name)
}
Write-Output 'Distribution checks passed. No keyboard hook was installed.'
