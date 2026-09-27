<#
.SYNOPSIS
	Install Rewards Farmer on Windows.

.DESCRIPTION
	The Windows counterpart of install.sh, with the same guarantees: it asks
	before anything that changes the machine, it prints the command it is about
	to run, and a missing Microsoft Edge is reported rather than treated as a
	fatal error.

	It brings a machine to the point where src\main.py runs: a supported Python,
	a virtualenv, the project dependencies, Edge and the two files the bot
	expects. Signing in is deliberately left to the user, because it needs a
	real browser window.

		.\install.bat                 install, asking before each system change
		.\install.bat -Yes            answer yes to everything
		.\install.bat -NoEdge         skip the Edge check
		.\install.bat -NoSchedule     do not offer to register the scheduled task
		.\install.bat -Dir PATH       install into PATH, cloning it if needed

.PARAMETER Yes
	Do not ask before steps that change the machine.

.PARAMETER NoEdge
	Skip the Microsoft Edge check.

.PARAMETER NoSchedule
	Do not register the scheduled task.

.PARAMETER Dir
	Where to install. Defaults to the current directory when it is a checkout,
	otherwise a rewards-farmer directory beside this script.

.NOTES
	Requires Windows 10 or later. Writes the virtualenv to .venv in the
	project, which is what scripts\windows\run-daily.ps1 looks for.
#>

[CmdletBinding()]
param(
	[switch] $Yes,
	[switch] $NoEdge,
	[switch] $NoSchedule,
	[string] $Dir
)

# Windows PowerShell 5.1 does not have $PSNativeCommandUseErrorActionPreference,
# and 7.3+ can be told to turn a native command's non-zero exit into a
# terminating error. Every native command below has its exit code read on
# purpose, so this is turned off on both, exactly as in run-daily.ps1.
$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:RepoUrl = 'https://github.com/g4zwr/rewards-farmer.git'
$script:RepoBranch = 'main'

# Must match requires-python in pyproject.toml. installer-lint.yml fails the
# build if the two drift apart, so this is a constant and not a discovery.
$script:PyMinMinor = 12

$script:VenvDirName = '.venv'
$script:ReqFileName = '.requirements.tmp'
$script:TaskName = 'RewardsFarmer'

# ------------------------------------------------------------------ output ----

function Write-Step { param([string] $Message) Write-Host ''; Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Info { param([string] $Message) Write-Host "    $Message" }
function Write-Ok   { param([string] $Message) Write-Host "    [ok] $Message" -ForegroundColor Green }
function Write-Warn { param([string] $Message) Write-Host "    [!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string] $Message) Write-Host "    [x] $Message" -ForegroundColor Red }

function Stop-WithError {
	param([string] $Message)
	Write-Err $Message
	exit 1
}

# Ask before doing anything that changes the machine, showing the command so the
# answer is an informed one.
function Confirm-Step {
	param(
		[string] $Prompt,
		[string] $Command
	)

	if ($Yes) {
		Write-Info "$Prompt (yes, -Yes)"
		return $true
	}

	Write-Info 'This would run:'
	Write-Host "       $Command" -ForegroundColor DarkGray

	if (-not [Environment]::UserInteractive) {
		Write-Warn "$Prompt"
		Write-Warn 'No console to ask on. Re-run with -Yes to allow it.'
		return $false
	}

	$reply = Read-Host "    $Prompt [y/N]"
	return $reply -match '^(y|yes)$'
}

# Run a native command with its output echoed, so the transcript shows what
# actually happened rather than only what was intended.
function Invoke-Native {
	param(
		[string] $FilePath,
		[string[]] $Arguments = @()
	)

	Write-Host "       > $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
	& $FilePath @Arguments
	return $LASTEXITCODE
}

# ----------------------------------------------------------- locate repo ----

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Already inside a checkout? Then work in place, no network needed.
if ((Test-Path (Join-Path $scriptDir 'pyproject.toml')) -and (Test-Path (Join-Path $scriptDir 'src'))) {
	$repoDir = $scriptDir
	$needsClone = $false
}
else {
	$repoDir = if ($Dir) { $Dir } else { Join-Path $scriptDir 'rewards-farmer' }
	$needsClone = $true
}

Write-Step 'Rewards Farmer installer'
Write-Info "platform   Windows"
Write-Info "target     $repoDir"

if ($needsClone) {
	$git = Get-Command git -ErrorAction SilentlyContinue
	if (-not $git) {
		Stop-WithError 'git is required to download the project. Install Git for Windows, or clone the repo yourself and run install.bat from inside it.'
	}
	Write-Step 'Downloading the project'
	if (Test-Path (Join-Path $repoDir '.git')) {
		if ((Invoke-Native $git.Source @('fetch', '--quiet', 'origin', $script:RepoBranch)) -ne 0) {
			Stop-WithError 'git fetch failed.'
		}
		if ((Invoke-Native $git.Source @('checkout', '--quiet', $script:RepoBranch)) -ne 0) {
			Stop-WithError 'git checkout failed.'
		}
		Write-Ok "updated to $script:RepoBranch"
	}
	else {
		if ((Invoke-Native $git.Source @('clone', '--quiet', '--depth', '1', '--branch', $script:RepoBranch, $script:RepoUrl, $repoDir)) -ne 0) {
			Stop-WithError 'git clone failed.'
		}
		Write-Ok "cloned $script:RepoBranch"
	}
}

if (-not (Test-Path (Join-Path $repoDir 'pyproject.toml'))) {
	Stop-WithError "No pyproject.toml in $repoDir - is this the right directory?"
}
Set-Location $repoDir

# ----------------------------------------------------------------- python ----

# Each candidate is an argument list rather than a bare name, because the py
# launcher selects the version and Windows resolves python.exe from PATH.
function Test-PythonCandidate {
	param([hashtable] $Candidate)
	# Interpolated from the declared minimum so the version is written down once,
	# which installer-lint.yml checks against pyproject.toml.
	$probe = "import sys; raise SystemExit(0 if sys.version_info >= (3, $script:PyMinMinor) else 1)"
	& $Candidate.Exe @($Candidate.Args) -c $probe *> $null
	return $LASTEXITCODE -eq 0
}

function Find-Python {
	$candidates = @(
		@{ Exe = 'py'; Args = @('-3.13') },
		@{ Exe = 'py'; Args = @('-3.12') },
		@{ Exe = 'py'; Args = @('-3') },
		@{ Exe = 'python'; Args = @() }
	)
	foreach ($candidate in $candidates) {
		if (-not (Get-Command $candidate.Exe -ErrorAction SilentlyContinue)) { continue }
		if (Test-PythonCandidate $candidate) { return $candidate }
	}
	return $null
}

function Get-PythonVersion {
	param([hashtable] $Candidate)
	$probe = 'import sys; print(".".join(str(n) for n in sys.version_info[:3]))'
	return (& $Candidate.Exe @($Candidate.Args) -c $probe)
}

Write-Step 'Checking Python'

$python = Find-Python
if ($python) {
	Write-Ok "Python $(Get-PythonVersion $python)"
}
else {
	Write-Warn "No Python $script:PyMinMinor+ found."
	$winget = Get-Command winget -ErrorAction SilentlyContinue
	if (-not $winget) {
		Stop-WithError "Python $script:PyMinMinor+ is required. Install it from python.org, then re-run install.bat."
	}
	$pythonArgs = @(
		'install', '--id', 'Python.Python.3.12', '--exact',
		'--accept-package-agreements', '--accept-source-agreements',
		'--disable-interactivity'
	)
	$pythonCommand = "winget $($pythonArgs -join ' ')"
	if (-not (Confirm-Step "Install Python $script:PyMinMinor+ now?" $pythonCommand)) {
		Stop-WithError "Python $script:PyMinMinor+ is required. Install it, then re-run install.bat."
	}
	if ((Invoke-Native $winget.Source $pythonArgs) -ne 0) {
		Stop-WithError 'Python installation failed. Install it manually, then re-run install.bat.'
	}
	# winget registers the py launcher, so no PATH refresh is needed for that
	# to find the interpreter it just installed.
	$python = Find-Python
	if (-not $python) {
		Stop-WithError "Python $script:PyMinMinor+ still not found after installing. Open a new terminal and re-run install.bat."
	}
	Write-Ok "Python $(Get-PythonVersion $python) installed"
}

# ------------------------------------------------------------ virtualenv ----

Write-Step 'Setting up the virtualenv'

$venvDir = Join-Path $repoDir $script:VenvDirName
$venvPython = Join-Path $venvDir 'Scripts\python.exe'

if (Test-Path $venvDir) { Write-Info 'reusing existing .venv' }
if (-not (Test-Path $venvPython)) {
	New-Item -ItemType Directory -Force -Path $venvDir | Out-Null
	$status = Invoke-Native $python.Exe ($python.Args + @('-m', 'venv', $venvDir))
	if ($status -ne 0 -or -not (Test-Path $venvPython)) {
		Stop-WithError 'Could not create .venv.'
	}
}
if (-not (Test-Path $venvPython)) {
	Stop-WithError "No interpreter at $venvPython"
}
Write-Ok "using Python $(& $venvPython -c 'import sys; print(".".join(str(n) for n in sys.version_info[:3]))') in .venv"

# ---------------------------------------------------------- dependencies ----

# Read the dependency list straight out of pyproject.toml so this script cannot
# drift from it. tomllib is in the standard library from 3.11.
Write-Step 'Installing dependencies'

$reqFile = Join-Path $repoDir $script:ReqFileName
$readDeps = @'
import tomllib
with open("pyproject.toml", "rb") as handle:
    project = tomllib.load(handle)["project"]
for dep in project["dependencies"]:
    print(dep.replace(" (", "(").replace(" )", ")"))
'@

Push-Location $repoDir
try {
	& $venvPython -c $readDeps | Set-Content -Path $reqFile -Encoding utf8
}
finally {
	Pop-Location
}

$depCount = 0
if (Test-Path $reqFile) {
	$depCount = @(Get-Content $reqFile | Where-Object { $_.Trim() }).Count
}
Write-Info "$depCount dependencies from pyproject.toml"

# A pip upgrade is nice to have, not required, so its failure is not fatal.
if ((Invoke-Native $venvPython @('-m', 'pip', 'install', '--quiet', '--upgrade', 'pip')) -ne 0) {
	Write-Warn 'could not upgrade pip; continuing'
}
if ((Invoke-Native $venvPython @('-m', 'pip', 'install', '--quiet', '-r', $reqFile)) -ne 0) {
	Stop-WithError 'Dependency installation failed.'
}
Remove-Item $reqFile -Force -ErrorAction SilentlyContinue
Write-Ok 'dependencies installed'

# ------------------------------------------------------------------- edge ----

function Test-Edge {
	foreach ($relative in @(
		'Microsoft\Edge\Application\msedge.exe',
		'Microsoft\Edge\Application\msedge_proxy.exe'
	)) {
		foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
			if (-not $root) { continue }
			if (Test-Path (Join-Path (Join-Path $root $relative))) { return $true }
		}
	}
	# Edge registers itself here on a normal install.
	if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe') { return $true }
	return $false
}

$edgeReady = $false
if ($NoEdge) {
	Write-Step 'Microsoft Edge'
	Write-Info 'skipped (-NoEdge)'
}
elseif (Test-Edge) {
	Write-Step 'Microsoft Edge'
	Write-Ok 'already installed'
	$edgeReady = $true
}
else {
	Write-Step 'Microsoft Edge'
	Write-Warn 'not found - the bot drives a real Edge, so this one is required.'
	$winget = Get-Command winget -ErrorAction SilentlyContinue
	if (-not $winget) {
		Write-Info 'No winget, so no automatic install. See the README for the manual step.'
	}
	else {
		$edgeArgs = @(
			'install', '--id', 'Microsoft.Edge', '--exact',
			'--accept-package-agreements', '--accept-source-agreements',
			'--disable-interactivity'
		)
		$edgeCommand = "winget $($edgeArgs -join ' ')"
		if (Confirm-Step 'Install Edge now?' $edgeCommand) {
			if ((Invoke-Native $winget.Source $edgeArgs) -eq 0 -and (Test-Edge)) {
				$edgeReady = $true
				Write-Ok 'installed'
			}
			else {
				Write-Warn 'Edge installation failed'
			}
		}
		else {
			Write-Warn 'skipped'
		}
	}
	if (-not $edgeReady) {
		Write-Info 'Everything else is ready; only Edge is still missing.'
	}
}

# --------------------------------------------------------- project files ----

Write-Step 'Project files'

# The bot uploads this image for the visual search task. It is gitignored
# because it is a downloaded binary, not source.
$imagePath = Join-Path $repoDir 'visual_search.jpg'
if (Test-Path $imagePath) {
	Write-Ok 'visual_search.jpg already present'
}
elseif ((Invoke-Native $venvPython @('src\random_image_for_visual_search.py')) -eq 0 -and (Test-Path $imagePath)) {
	Write-Ok 'generated visual_search.jpg'
}
else {
	Write-Warn 'could not generate visual_search.jpg - only the visual search task needs it'
}

$envPath = Join-Path $repoDir '.env'
if (Test-Path $envPath) {
	Write-Ok '.env already present (left alone)'
}
else {
	Copy-Item (Join-Path $repoDir '.env.example') $envPath
	Write-Ok 'created .env from .env.example'
}

# -------------------------------------------------------------- schedule ----

if ($NoSchedule) {
	Write-Step 'Daily schedule'
	Write-Info 'skipped (-NoSchedule)'
}
elseif (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
	Write-Step 'Daily schedule'
	Write-Warn 'Task Scheduler not available - skipping. See the README for Task Scheduler setup.'
}
else {
	Write-Step 'Daily schedule'
	$runner = Join-Path $repoDir 'scripts\windows\run-daily.ps1'
	if (-not (Test-Path $runner)) {
		Write-Warn "missing $runner"
	}
	else {
		$taskCommand = "Register-ScheduledTask -TaskName '$script:TaskName' (08:00 and 20:00, daily)"
		if (Confirm-Step 'Register the scheduled task (runs at 08:00 and 20:00)?' $taskCommand) {
			try {
				$action = New-ScheduledTaskAction `
					-Execute 'powershell.exe' `
					-Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runner`""
				$triggers = @(
					(New-ScheduledTaskTrigger -Daily -At '08:00'),
					(New-ScheduledTaskTrigger -Daily -At '20:00')
				)
				# Interactive logon: the task needs a desktop session, and
				# "run whether logged on or not" would need a stored password.
				$principal = New-ScheduledTaskPrincipal `
					-UserId "$env:USERDOMAIN\$env:USERNAME" `
					-LogonType Interactive `
					-RunLevel Limited
				Register-ScheduledTask `
					-TaskName $script:TaskName `
					-Action $action `
					-Trigger $triggers `
					-Principal $principal `
					-Description 'Runs the Rewards Farmer once in the morning and once in the evening.' `
					-Force | Out-Null
				Write-Ok "registered '$script:TaskName'"
			}
			catch {
				Write-Warn "could not register the task: $($_.Exception.Message)"
				Write-Info "you can create it by hand from $runner"
			}
		}
	}
}

# --------------------------------------------------------------- summary ----

Write-Step 'Done'
Write-Ok 'installed'

Write-Host ''
Write-Host '    One thing left is manual, by design: signing in.'
Write-Host ''
Write-Host "      $venvPython src\main.py"
Write-Host ''
Write-Host '    A browser opens. Sign in to Bing and to rewards.bing.com, then press'
Write-Host '    Ctrl-C. From then on it runs unattended:'
Write-Host ''
Write-Host "      $venvPython src\main.py          # or scripts\windows\run-daily.ps1 for the once-a-day guard"
Write-Host ''

if (-not $edgeReady) {
	Write-Warn 'Microsoft Edge is still not installed - the bot will not start without it.'
}

exit 0
