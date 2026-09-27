@echo off
REM Rewards Farmer installer for Windows.
REM
REM This is deliberately only a launcher. The logic lives in
REM scripts\bootstrap\install.ps1, because batch cannot do the version checks
REM and the prompting this needs without becoming unreadable.
REM
REM Double-click this file to install with prompts, or run it from a terminal:
REM     install.bat
REM     install.bat -Yes
REM     install.bat -NoEdge -NoSchedule

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%scripts\bootstrap\install.ps1"

if not exist "%PS_SCRIPT%" (
    echo [x] Cannot find "%PS_SCRIPT%".
    echo     Run this from inside a checkout of the project.
    goto :fail
)

REM Prefer PowerShell 7 when it is installed, but Windows PowerShell 5.1 ships
REM with Windows and is enough: the script is written for both.
set "PS_EXE="
where pwsh.exe >nul 2>&1 && set "PS_EXE=pwsh.exe"
if not defined PS_EXE where powershell.exe >nul 2>&1 && set "PS_EXE=powershell.exe"

if not defined PS_EXE (
    echo [x] Neither pwsh.exe nor powershell.exe was found.
    echo     Enable Windows PowerShell under "Turn Windows features on or off",
    echo     or install PowerShell 7, then run this again.
    goto :fail
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "RC=%ERRORLEVEL%"

REM A double-clicked window closes the moment the script exits, which would hide
REM both the summary and any question still waiting. Only wait when there were no
REM arguments, since that is the double-click case.
if "%~1"=="" (
    echo.
    pause
)

exit /b %RC%

:fail
echo.
pause
exit /b 1
