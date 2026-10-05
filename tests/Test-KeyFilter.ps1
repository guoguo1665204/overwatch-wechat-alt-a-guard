$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'src\AltAGuard.cs')))
$script:count = 0
function Assert([bool]$actual, [bool]$expected, [string]$name) {
    if ($actual -ne $expected) { throw "FAILED: $name (actual=$actual expected=$expected)" }
    $script:count++
    Write-Output "PASS: $name"
}
$f = [OverwatchAltAGuard.KeyFilter]::new()
Assert ($f.Filter(0x41,$false,$true,$true)) $true 'Alt+A in game blocked'
Assert ($f.Filter(0x41,$false,$true,$true)) $true 'Alt+A autorepeat blocked'
Assert ($f.BlockedPresses -eq 1) $true 'Held key counted once'
Assert ($f.Filter(0x41,$true,$false,$false)) $true 'Blocked release swallowed after focus change'
Assert ($f.Filter(0x41,$false,$false,$true)) $false 'Ordinary A passes'
Assert ($f.Filter(0x41,$true,$false,$true)) $false 'Ordinary A release passes'
Assert ($f.Filter(0x41,$false,$true,$false)) $false 'Outside game Alt+A passes'
Assert ($f.Filter(0x41,$true,$true,$false)) $false 'Outside game release passes'
Assert ($f.Filter(0x42,$false,$true,$true)) $false 'Alt+B unchanged'
Assert ($f.Filter(0x09,$false,$true,$true)) $false 'Alt+Tab unchanged'
Assert ($f.Filter(0x73,$false,$true,$true)) $false 'Alt+F4 unchanged'
foreach ($modifier in @(0xA0,0xA1,0xA2,0xA3,0x5B,0x5C,0x10,0x11)) {
    Assert ($f.Filter($modifier,$false,$false,$true)) $false "Modifier $modifier passes"
    Assert ($f.Filter(0x41,$false,$true,$true)) $false "Extra modifier $modifier + Alt+A unchanged"
    Assert ($f.Filter(0x41,$true,$true,$true)) $false 'Extra-modifier release passes'
    [void]$f.Filter($modifier,$true,$false,$true)
}
Assert ($f.Filter(0x41,$false,$false,$true)) $false 'A held before Alt passes'
Assert ($f.Filter(0x41,$false,$true,$true)) $true 'Repeat after Alt held blocked'
Assert ($f.Filter(0x41,$true,$true,$true)) $false 'Previously delivered A gets release'
Assert ($f.Filter(0x41,$false,$true,$true)) $true 'New press blocked'
Assert ($f.Filter(0x41,$false,$false,$true)) $false 'A resumes after Alt released'
Assert ($f.Filter(0x41,$true,$false,$true)) $false 'Resumed A gets release'
$f = [OverwatchAltAGuard.KeyFilter]::new()
$f.SeedA($true)
Assert ($f.Filter(0x41,$false,$true,$true)) $true 'Held A at startup has repeat blocked'
Assert ($f.Filter(0x41,$true,$true,$true)) $false 'Held A at startup still gets release'
Write-Output "TOTAL: $script:count checks passed"
