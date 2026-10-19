# Writes what the install test compares, for the current user, into a folder (one file per item, text, sorted, so two
# snapshots diff cleanly):
#
#   languages.txt      the user's language list (Get-WinUserLanguageList: tags and their input methods, in order)
#   languages.xml      the same, as Export-Clixml, to restore it with Set-WinUserLanguageList
#   default.txt        the default input method override (Get-WinDefaultInputMethodOverride)
#   hkcu-*.txt         HKCU keys an input method's install touches: the language list's own (User Profile, its
#                      System Backup), Keyboard Layout, CTF; values sorted within each key
#   preload.reg        HKCU\Keyboard Layout\Preload as reg export, to put it back
#   ours.txt           everything of AllInOneIME's: its keys in HKLM and HKCU, the Run entry, its files, and
#                      pending renames that name it
#
#   powershell -ExecutionPolicy Bypass -File snapshot.ps1 -Out <folder>

param([Parameter(Mandatory = $true)][string]$Out)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$clsid = '{DBB94280-C4C2-4C91-816F-79BB471AFE56}'

function Write-Lines($name, $lines) {
    $path = Join-Path $Out $name
    $lines = [string[]]@($lines | Where-Object { $null -ne $_ })   # nothing at all: an empty file
    $text = if ($lines.Count) { ($lines -join "`n") + "`n" } else { '' }   # LF, as the test's sed and diff write
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

$list = Get-WinUserLanguageList
$list | Export-Clixml (Join-Path $Out 'languages.xml')
Write-Lines 'languages.txt' ($list | ForEach-Object { '{0}: {1}' -f $_.LanguageTag, ($_.InputMethodTips -join ', ') })
Write-Lines 'default.txt' @("override: [$(Get-WinDefaultInputMethodOverride)]")

# A key and everything under it, one line per key and per value, sorted.
function Dump-Key($path) {
    if (-not (Test-Path $path)) { return @("(no $path)") }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in @(Get-Item $path) + @(Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue)) {
        $name = $key.Name
        $lines.Add("[$name]")
        foreach ($value in $key.GetValueNames()) {
            $data = $key.GetValue($value, $null, 'DoNotExpandEnvironmentNames')
            if ($data -is [array]) { $data = ($data | ForEach-Object { "$_" }) -join '|' }
            $lines.Add("[$name] ""$value""=$data")
        }
    }
    return $lines | Sort-Object
}

Write-Lines 'hkcu-user-profile.txt' (Dump-Key 'HKCU:\Control Panel\International\User Profile')
Write-Lines 'hkcu-user-profile-backup.txt' (Dump-Key 'HKCU:\Control Panel\International\User Profile System Backup')
Write-Lines 'hkcu-keyboard-layout.txt' (Dump-Key 'HKCU:\Keyboard Layout')
Write-Lines 'hkcu-ctf.txt' (Dump-Key 'HKCU:\Software\Microsoft\CTF')
& reg.exe export 'HKCU\Keyboard Layout\Preload' (Join-Path $Out 'preload.reg') /y | Out-Null

# AllInOneIME's own traces.
$ours = New-Object System.Collections.Generic.List[string]
foreach ($path in "HKLM:\Software\Classes\CLSID\$clsid", "HKLM:\Software\Microsoft\CTF\TIP\$clsid",
                  'HKLM:\Software\AllInOneIME', "HKCU:\Software\Microsoft\CTF\TIP\$clsid") {
    if (Test-Path $path) { $ours.Add("key: $path") }
}
$run = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).AllInOneIME
if ($run) { $ours.Add("run: $run") }
foreach ($line in (Dump-Key 'HKCU:\Software\Microsoft\CTF') + (Dump-Key 'HKCU:\Control Panel\International\User Profile')) {
    if ($line -match [regex]::Escape($clsid)) { $ours.Add("hkcu: $line") }
}
$uninstall = Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
    Where-Object { $_.GetValue('DisplayName') -eq 'AllInOneIME' }
foreach ($entry in $uninstall) { $ours.Add("installed: $($entry.PSChildName) $($entry.GetValue('DisplayVersion'))") }
$folder = Join-Path ${env:ProgramFiles} 'AllInOneIME'
if (Test-Path $folder) {
    foreach ($file in Get-ChildItem $folder -Recurse) { $ours.Add("file: $($file.FullName)") }
}
$pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations
foreach ($op in @($pending)) { if ($op -match 'AllInOneIME') { $ours.Add("pending: $op") } }
Write-Lines 'ours.txt' ($ours | Sort-Object)
