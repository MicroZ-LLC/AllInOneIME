@echo off
rem Builds the text service and its tests with MSBuild (no Developer shell needed: vswhere finds MSBuild).
rem
rem   build.cmd [Release|Debug|all] [x64]
rem
rem Outputs go to build\<Platform>\<Configuration>\.
setlocal
set "CONFIG=%~1"
if "%CONFIG%"=="" set "CONFIG=Release"
set "PLATFORM=%~2"
if "%PLATFORM%"=="" set "PLATFORM=x64"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "MSBUILD="
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe`) do set "MSBUILD=%%i"
if not defined MSBUILD (
    echo MSBuild not found: install Visual Studio Build Tools 2022 with the C++ workload and a Windows SDK.
    exit /b 1
)
set VSLANG=1033
if /i "%CONFIG%"=="all" (
    "%MSBUILD%" "%~dp0AllInOneTIP.sln" -nologo -m -v:minimal -p:Configuration=Debug -p:Platform=%PLATFORM% || exit /b 1
    "%MSBUILD%" "%~dp0AllInOneTIP.sln" -nologo -m -v:minimal -p:Configuration=Release -p:Platform=%PLATFORM% || exit /b 1
    exit /b 0
)
"%MSBUILD%" "%~dp0AllInOneTIP.sln" -nologo -m -v:minimal -p:Configuration=%CONFIG% -p:Platform=%PLATFORM%
