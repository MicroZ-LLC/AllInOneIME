# Builds AllInOneIME for Windows in Release and packages it as an MSI (WiX Toolset 5).
#
#   powershell -ExecutionPolicy Bypass -File Windows\installer\build.ps1 [-SkipBuild] [-Output <file.msi>]
#
# 1. the TSF DLL (Windows\tip\AllInOneTIP.vcxproj) and the installer's helper (setup\AllInOneIMESetup.vcxproj), with
#    MSBuild, into Windows\installer\build\ (not the tip's build folder, whose DLL a test may have left loaded in an app);
# 2. the engine and the command line, `swift build -c release --product AllInOneIMEEngine` and `allinoneime-cli` in
#    Windows\, on librime and rime-ice's data in ThirdParty (Windows\Scripts\build-rime-data.sh makes them, run here
#    with Git Bash when they aren't there);
# 3. the stage, Windows\installer\build\stage\: the four programs, the engine made a GUI-subsystem program (editbin),
#    so that started at logon it opens no console window; librime (rime.dll) and its data (rime-data\: rime-ice's
#    schemas and prebuilt dictionaries) beside the engine; and in runtime\ the DLLs the engine and the command line
#    need (dumpbin, transitively) from the Swift runtime and the VC++ redistributable;
# 4. Windows\installer\build\AllInOneIME-<version>-x64.msi, with `wix build`. The version is the app's
#    (Resources\Info.plist, CFBundleShortVersionString).
#
# Needs Visual Studio Build Tools 2022 (MSVC, a Windows SDK), Swift 6.4 for Windows, and WiX 5 as a .NET tool
# (`dotnet tool install --global wix --version 5.0.2`; the UI and Util extensions are added here if missing).
# -SkipBuild packages what was built last. Each package gets a product code of its own, so a second one of the same
# version installs over the first as an upgrade (the install test does that, with -Output).

param([switch]$SkipBuild, [string]$Output)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$windows = Split-Path $here -Parent
$repo = Split-Path $windows -Parent
$tip = Join-Path $windows 'tip'
$out = Join-Path $here 'build'
$stage = Join-Path $out 'stage'
$wixVersion = '5.0.2'

function Fail($message) { Write-Host "build.ps1: $message"; exit 1 }

function Run($exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { Fail "$exe failed ($LASTEXITCODE)" }
}

# ---- the tools ----

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { Fail 'no vswhere: install Visual Studio Build Tools 2022 with the C++ workload' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { Fail 'no Visual Studio with the C++ tools' }
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' |
    Select-Object -First 1
$vcVersion = (Get-Content (Join-Path $vs 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt')).Trim()
$vcBin = Join-Path $vs "VC\Tools\MSVC\$vcVersion\bin\Hostx64\x64"
$dumpbin = Join-Path $vcBin 'dumpbin.exe'
$editbin = Join-Path $vcBin 'editbin.exe'
$vcRedist = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } | Where-Object { Test-Path $_ } |
    Select-Object -Last 1

$swiftCore = Get-Command swiftCore.dll -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $swiftCore) { Fail 'the Swift runtime (swiftCore.dll) is not on PATH: install Swift for Windows' }
$swiftRuntime = Split-Path $swiftCore.Source -Parent

$wix = Get-Command wix -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wix) {
    $candidate = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe'
    if (Test-Path $candidate) { $wix = Get-Item $candidate }
}
if (-not $wix) { Fail "no wix: dotnet tool install --global wix --version $wixVersion" }
$wix = if ($wix.Source) { $wix.Source } else { $wix.FullName }
$extensions = & $wix extension list -g
foreach ($ext in 'WixToolset.UI.wixext', 'WixToolset.Util.wixext') {
    if (-not ($extensions | Select-String -SimpleMatch $ext)) { Run $wix @('extension', 'add', '-g', "$ext/$wixVersion") }
}

# librime and rime-ice's data, as the Rime tests and the engine's use them.
$thirdParty = if ($env:ALLINONEIME_THIRDPARTY) { $env:ALLINONEIME_THIRDPARTY } else { Join-Path $windows 'ThirdParty' }
$rimeDll = Join-Path $thirdParty 'librime\dist\lib\rime.dll'
$rimeData = Join-Path $thirdParty 'rime-data'
if (-not $SkipBuild -and (-not (Test-Path $rimeDll) -or -not (Test-Path (Join-Path $rimeData 'build\rime_ice.table.bin')))) {
    $bash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    if (-not (Test-Path $bash)) { Fail "no librime and rime-data in ${thirdParty}: run Windows/Scripts/build-rime-data.sh in Git Bash" }
    Write-Host '== librime and rime-ice (Scripts/build-rime-data.sh)'
    Run $bash @((Join-Path $windows 'Scripts\build-rime-data.sh'))
}

# The version: the app's.
$plist = Get-Content -Raw -Encoding UTF8 (Join-Path $repo 'Resources\Info.plist')
$version = if ($plist -match '<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>') { $Matches[1] }
if ($version -notmatch '^\d+\.\d+\.\d+$') { Fail "no version in Resources\Info.plist ($version)" }
Write-Host "AllInOneIME $version"

# ---- 1, 2: build ----

$tipOut = Join-Path $out 'x64\Release\'
if (-not $SkipBuild) {
    $env:VSLANG = '1033'
    Write-Host '== the text service and the setup helper (MSBuild, Release x64)'
    Run $msbuild @((Join-Path $tip 'AllInOneTIP.vcxproj'), '-nologo', '-v:minimal', '-p:Configuration=Release',
        '-p:Platform=x64', "-p:OutDir=$tipOut", "-p:IntDir=$(Join-Path $out 'obj\AllInOneTIP\')")
    Run $msbuild @((Join-Path $here 'setup\AllInOneIMESetup.vcxproj'), '-nologo', '-v:minimal',
        '-p:Configuration=Release', '-p:Platform=x64')
    Write-Host '== the engine and the command line (swift build -c release)'
    Push-Location $windows
    try {
        Run 'swift' @('build', '-c', 'release', '--product', 'AllInOneIMEEngine')
        Run 'swift' @('build', '-c', 'release', '--product', 'allinoneime-cli')
    } finally { Pop-Location }
}

# ---- 3: the stage ----

Write-Host '== the stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$runtime = Join-Path $stage 'runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$engineBuilt = Join-Path $windows '.build\release\AllInOneIMEEngine.exe'
$cliBuilt = Join-Path $windows '.build\release\allinoneime-cli.exe'
foreach ($file in (Join-Path $tipOut 'AllInOneTIP.dll'), (Join-Path $tipOut 'AllInOneIMESetup.exe'), $engineBuilt, $cliBuilt,
                  $rimeDll) {
    if (-not (Test-Path $file)) { Fail "not built: $file" }
    Copy-Item $file $stage
}
$engine = Join-Path $stage 'AllInOneIMEEngine.exe'
Run $editbin @('/nologo', '/SUBSYSTEM:WINDOWS', $engine)
# rime-ice's data, whole: the schemas, the dictionaries' sources and the dictionaries prebuilt from them (build\), which
# librime uses as they are once it has checked them against the sources.
if (-not (Test-Path (Join-Path $rimeData 'build\rime_ice.table.bin'))) { Fail "no prebuilt rime-data in $rimeData" }
Copy-Item $rimeData (Join-Path $stage 'rime-data') -Recurse
$dataFiles = Get-ChildItem (Join-Path $stage 'rime-data') -Recurse -File
Write-Host ("  rime-data: {0} files, {1:N1} MB; rime.dll {2:N1} MB" -f $dataFiles.Count,
    (($dataFiles | Measure-Object Length -Sum).Sum / 1MB), ((Get-Item $rimeDll).Length / 1MB))

# The DLLs a module imports, by name.
function Imports($module) {
    $lines = & $dumpbin /nologo /dependents $module
    $in = $false
    foreach ($line in $lines) {
        if ($line -match 'Image has the following dependencies') { $in = $true; continue }
        if ($in -and $line -match '^\s*Summary') { break }
        if ($in -and $line -match '^\s+(\S+\.dll)\s*$') { $Matches[1] }
    }
}

# The engine's and the command line's imports, transitively, that come from the VC++ redistributable or the Swift
# runtime (the rest is Windows': KERNEL32, the UCRT's api-ms-win-crt-*; rime.dll has its C++ runtime built in).
$queue = New-Object System.Collections.Queue
$queue.Enqueue($engine)
$queue.Enqueue((Join-Path $stage 'allinoneime-cli.exe'))
$seen = @{}
while ($queue.Count -gt 0) {
    foreach ($name in Imports $queue.Dequeue()) {
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $source = $null
        foreach ($dir in $vcRedist, $swiftRuntime) {
            if ($dir -and (Test-Path (Join-Path $dir $name))) { $source = Join-Path $dir $name; break }
        }
        if (-not $source) { continue }
        Copy-Item $source $runtime
        $queue.Enqueue((Join-Path $runtime (Split-Path $source -Leaf)))
    }
}
$runtimeFiles = Get-ChildItem $runtime
Write-Host ("  runtime: {0} DLLs, {1:N1} MB, from {2} and {3}" -f $runtimeFiles.Count,
    (($runtimeFiles | Measure-Object Length -Sum).Sum / 1MB), $swiftRuntime, $vcRedist)

# The license, as RTF for the installer's dialog.
$license = Get-Content (Join-Path $repo 'LICENSE') -Encoding UTF8
$rtf = New-Object System.Text.StringBuilder
[void]$rtf.Append('{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\fs18 ')
foreach ($line in $license) {
    $escaped = $line.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}')
    $escaped = [regex]::Replace($escaped, '[^\x00-\x7F]', { param($m) '\u{0}?' -f [int][char]$m.Value })
    [void]$rtf.Append($escaped).Append('\par ')
}
[void]$rtf.Append('}')
$licenseRtf = Join-Path $out 'License.rtf'
[System.IO.File]::WriteAllText($licenseRtf, $rtf.ToString(), [System.Text.Encoding]::ASCII)

# ---- 4: the MSI ----

$msi = if ($Output) { [System.IO.Path]::GetFullPath($Output) } else { Join-Path $out "AllInOneIME-$version-x64.msi" }
Write-Host "== $msi"
Run $wix @('build', '-nologo', '-arch', 'x64', '-ext', 'WixToolset.UI.wixext', '-ext', 'WixToolset.Util.wixext',
    '-d', "Version=$version", '-d', "StageDir=$stage", '-d', "TipDir=$tip", '-d', "LicenseRtf=$licenseRtf",
    '-intermediatefolder', (Join-Path $out 'wixobj'), '-o', $msi, (Join-Path $here 'AllInOneIME.wxs'))
Write-Host ("built {0} ({1:N1} MB)" -f $msi, ((Get-Item $msi).Length / 1MB))
