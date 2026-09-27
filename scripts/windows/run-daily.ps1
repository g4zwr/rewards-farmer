<#
.SYNOPSIS
	Run the Microsoft Rewards farmer at most once per local day.

.DESCRIPTION
	The Windows counterpart of scripts/run_daily.sh, with the same three
	guarantees: one run at a time, no browser opened once the day's work is
	done, and the day only marked on a clean exit so a failed run can be
	retried.

	Run it by hand any time; it is safe to do so.

		powershell -ExecutionPolicy Bypass -File scripts\windows\run-daily.ps1

.NOTES
	State lives in %LOCALAPPDATA%\rewards-farmer, not in the repo, so nothing
	here can be committed by accident and `git status` stays clean.
#>

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ can be told to turn a native command's non-zero exit into a
# terminating error. That is fine everywhere except here: the whole point is to
# read that exit code and decide whether the day counts. Windows PowerShell 5.1
# ignores this variable, so setting it unconditionally is safe on both.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stateDir = Join-Path $env:LOCALAPPDATA 'rewards-farmer'
$logDir = Join-Path $stateDir 'logs'

# The Windows equivalent of ~/.local/state. Not worth putting under the repo,
# where a stray file would show up in `git status`.
New-Item -ItemType Directory -Force -Path $stateDir, $logDir | Out-Null

$today = Get-Date -Format 'yyyy-MM-dd'
$marker = Join-Path $stateDir "last-success-$today"
$logFile = Join-Path $logDir "run-$today.log"
$lockFile = Join-Path $stateDir 'run.lock'

# One farmer at a time. Two Edge instances sharing data-dir\ makes the second
# one fail to start, and a scheduled run colliding with a manual one would
# report a browser error rather than anything useful. Holding the file with
# exclusive access is released by the OS when this process exits, including
# when it is killed -- which is the case flock and mkdir cannot both promise.
$lock = $null

try {
	try {
		$lock = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
	}
	catch [System.IO.IOException] {
		Write-Host "run-daily: another run holds $lockFile, nothing to do."
		exit 0
	}

	if (Test-Path $marker) {
		Write-Host "run-daily: already ran today ($today), skipping. Log: $logFile"
		exit 0
	}

	# A venv is what the install steps produce. Fall back to poetry so a fresh
	# clone still runs.
	$venvPython = Join-Path $repoRoot '.venv\Scripts\python.exe'

	if (Test-Path $venvPython) {
		$python = $venvPython
		$pythonArgs = @()
	}
	elseif (Get-Command poetry -ErrorAction SilentlyContinue) {
		$python = 'poetry'
		$pythonArgs = @('run', 'python')
	}
	else {
		Write-Error 'run-daily: no .venv and no poetry on PATH.'
		exit 2
	}

	# Headless is what makes this schedulable, and it is the mode the Docker
	# image already uses. Two reasons:
	#
	#   - main.py waits on input("Press Enter to exit...") when not headless,
	#     and Task Scheduler has no console, so that raises EOFError after the
	#     day's work is already done and the task exits non-zero for no reason.
	#   - it needs no interactive session, so the run does not depend on you
	#     being logged in at that hour.
	#
	# main.py loads .env with python-dotenv's default override=False, so setting
	# this wins over the REWARDS_HEADLESS=false in .env.
	$env:REWARDS_HEADLESS = 'true'

	Write-Host "run-daily: starting $today, logging to $logFile"

	Push-Location $repoRoot
	& $python @pythonArgs 'src\main.py' *>> $logFile
	$status = $LASTEXITCODE
	Pop-Location

	if ($status -eq 0) {
		# main.py returns 0 when the browser started and the run finished, 1
		# when it never started, 2 on bad config. Only the first is worth
		# remembering.
		New-Item -ItemType File -Force -Path $marker | Out-Null
		Write-Host "run-daily: finished, marked $today done."
		exit 0
	}

	Write-Host "run-daily: run failed (exit $status), not marking $today done so a later" -ForegroundColor Yellow
	Write-Host "run-daily: run today still tries. Log: $logFile" -ForegroundColor Yellow
	exit $status
}
finally {
	if ($lock) { $lock.Dispose() }
}
