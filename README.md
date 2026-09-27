<div align="center">

# Rewards Farmer

<p align="center">
  <strong>Desktop Microsoft Rewards Automation</strong>
</p>

<a href="https://git.io/typing-svg">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=20&pause=1000&color=FFFFFF&background=00000000&center=true&vCenter=true&width=680&height=100&lines=Microsoft+Rewards+Automation+on+Desktop;Headless+Runs+at+Most+Once+A+Day;Windows+%2F+Linux+%2F+macOS+Scheduling;Task+Scheduler+%2F+systemd+%2F+launchd" alt="Typing Animation" />
</a>

<br />

<img src="https://img.shields.io/badge/Language-Python-000000?style=for-the-badge&logo=python&logoColor=white" alt="Python" />
<img src="https://img.shields.io/badge/Automation-Selenium-000000?style=for-the-badge&logo=selenium&logoColor=white" alt="Selenium" />
<img src="https://img.shields.io/badge/Platform-Windows_%2F_Linux_%2F_macOS-000000?style=for-the-badge" alt="Platform" />
<img src="https://img.shields.io/badge/Scheduling-Headless_Twice_Daily-000000?style=for-the-badge" alt="Scheduling" />
<img src="https://img.shields.io/badge/License-MIT-000000?style=for-the-badge" alt="License" />

---

</div>

## Demonstration

The technique this is based on, by the original author:

https://youtu.be/4qdPcMNaioA

A real unattended run on Linux, taken verbatim from the log of a first
execution on a signed-in profile. The search quota went from `6/15` to a
complete `15/15`, and the daily set, the cards and the bonus all closed out:

```text
11:37:35 INFO     rewards_tasks: [OK] Bing daily set
11:37:39 WARNING  rewards_tasks: [SKIP] Explore on Bing: not available in this UI variant (NoSuchElementException)
11:37:54 WARNING  rewards_tasks: [SKIP] Visual search: not available in this UI variant (ElementNeverAppeared)
11:38:34 INFO     rewards_tasks: [OK] Misc cards
11:38:45 INFO     rewards_tasks: Search points before: 6/15
11:40:13 INFO     rewards_tasks: Round 1: 3 searches -> 15/15
11:40:13 INFO     rewards_tasks: Search quota complete: 15/15
11:40:13 INFO     rewards_tasks: [OK] Required searches
11:40:27 INFO     rewards_tasks: [OK] Bonus points
```

The two `[SKIP]` lines are expected rather than broken — see
[Troubleshooting](#troubleshooting).

The same run a second time does nothing at all — see
[Daily Scheduling](#daily-scheduling).

---

## Installation & Usage

> **Use at your own risk.** Microsoft may take action against your account for
> using automated scripts to gain rewards points. The video above covers the
> techniques used to reduce detection. Nothing here changes your account's
> standing in Microsoft's eyes.

### One command (recommended)

**Windows** — download `install.bat` from the
[latest release](https://github.com/g4zwr/rewards-farmer/releases/latest) and
double-click it. A console opens, asks a few questions, and does the rest. The
same archive works from PowerShell with `.\install.ps1`.

**macOS and Linux** — clone, then run the installer:

```sh
git clone https://github.com/g4zwr/rewards-farmer
cd rewards-farmer
./install.sh
```

The installer sets up everything needed to run: a private `.venv`, the
dependencies, the image the visual-search task uploads, a `.env`, and a daily
schedule. It never installs a system package without first printing the exact
command and waiting for you to agree, so you always see what a `sudo` will do.

Both installers accept a few switches:

| Switch | Effect |
| --- | --- |
| `-y`, `--yes` / `-Yes` | Answer yes to everything. Useful in CI; read the first bullet above before using it unattended. |
| `--no-edge` / `-NoEdge` | Skip Microsoft Edge installation and report it if missing. |
| `--no-schedule` / `-NoSchedule` | Set up the project but do not register the daily job. |
| `--dir PATH` / `-Dir PATH` | Install somewhere other than the current directory. |
| `--help` | Print the usage text and exit. |

Edge itself is the one hard requirement. If it cannot be installed, the installer
says so and continues, because the rest of the setup is still worth having — the
run will stop later, with a clear message, rather than here.

**Signing in is the only genuinely manual part of the whole project.** The
installer finishes by printing the command to start it; the first run opens a
visible window so you can sign in to Bing and to `rewards.bing.com` by hand,
after which it runs unattended. See [If Edge will not start](#if-edge-will-not-start)
if the window does not appear.

<details>
<summary><strong>Manual setup (if you would rather not use the installer)</strong></summary>

These steps are the same ones the installer performs, written out for the case
where you want to run them yourself. They assume `git clone` and `poetry`.

<details>
<summary><strong>Windows (PowerShell)</strong></summary>

```powershell
# 1. Python 3.12 or newer
winget install Python.Python.3.12

# 2. Poetry
irm https://install.python-poetry.org | iex

# 3. Dependencies
cd C:\rewards-farmer
poetry install
poetry env activate

# 4. Edge + driver: Windows already has Edge, and Selenium Manager fetches a
#    matching msedgedriver on its own. Nothing to do here.

# 5. The image the visual search task uploads (gitignored, never shipped)
python src\random_image_for_visual_search.py

# 6. First run: opens a visible window, sign in on both Bing and
#    rewards.bing.com, then press Ctrl-C to quit
python src\main.py

# 7. Normal runs
python src\main.py
```

If `poetry env activate` fails with *"Cannot bind argument to parameter
'Command' because it is null"*, `poetry install` did not create an
environment. Run `python --version` first: an older Python leaves poetry with
nothing to activate, and the message explaining that goes to stderr rather than
into `iex`. Older poetry also wants `iex (poetry env activate)`.

</details>

<details>
<summary><strong>Arch Linux (and other Linux)</strong></summary>

```sh
# 1. Python 3.12 or newer — Arch ships 3.13+, so a plain install is current
sudo pacman -S --needed python python-pip

# 2. Poetry
pipx install poetry          # or: sudo pacman -S poetry

# 3. Edge
yay -S microsoft-edge-stable-bin     # AUR; drop the yay for your helper

# 4. Dependencies
cd ~/rewards-farmer
poetry install
eval $(poetry env activate)

# 5. The image the visual search task uploads (gitignored, never shipped)
python src/random_image_for_visual_search.py

# 6. First run: opens a visible window, sign in on both Bing and
#    rewards.bing.com, then press Ctrl-C to quit
python src/main.py

# 7. Normal runs
python src/main.py
```

**No root, and no display, are needed at run time.** The `keyboard` and
`pygame` dependencies are imported only by `src/recordpress.py` and
`src/visualize_bezier_distortions.py`, which are standalone helpers that no
other module imports. Nothing on the main path needs `/dev/input` or an X or
Wayland session, which is exactly why the headless scheduler below works on a
machine nobody is sitting at.

Selenium Manager locates Edge and fetches a matching `msedgedriver` on its own.
If it struggles, name both explicitly — the two versions must match exactly or
the driver refuses to connect:

```sh
sudo install -m755 msedgedriver /usr/local/bin/msedgedriver
export EDGE_BINARY=/usr/bin/microsoft-edge-stable
export MSEDGEDRIVER_PATH=/usr/local/bin/msedgedriver
```

</details>

<details>
<summary><strong>macOS</strong></summary>

```sh
# 1. Python 3.12 or newer — Homebrew's python3 is already past that
brew install python

# 2. Poetry
brew install poetry

# 3. Edge
brew install --cask microsoft-edge

# 4. Dependencies
cd ~/rewards-farmer
poetry install
eval $(poetry env activate)

# 5. The image the visual search task uploads (gitignored, never shipped)
python src/random_image_for_visual_search.py

# 6. First run: opens a visible window, sign in on both Bing and
#    rewards.bing.com, then press Ctrl-C to quit
python src/main.py

# 7. Normal runs
python src/main.py
```

Selenium Manager handles the driver as it does everywhere else. If you install
`msedgedriver` by hand, point at it with `MSEDGEDRIVER_PATH` — the versions
must match exactly.

</details>

</details>

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Daily Scheduling](#daily-scheduling)
- [Configuration](#configuration)
- [Docker](#docker)
- [Running more than one account](#running-more-than-one-account)
- [If Edge will not start](#if-edge-will-not-start)
- [Logging](#logging)
- [Windows Virtual Desktop](#windows-virtual-desktop)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)
- [License](#license)

---

## Overview

**Rewards Farmer** drives a real Microsoft Edge with Selenium to complete the
daily Microsoft Rewards tasks on a desktop. The six tasks it knows about are:

```text
Bing daily set  ·  Explore on Bing  ·  Visual search
Misc cards      ·  Required searches  ·  Bonus points
```

Two of them depend on an en-US Bing layout — Explore and Visual search — and
report `[SKIP]` rather than failing when that layout is not what is on screen.

It is written to be **re-runnable**. Every task checks whether it is already
complete before acting, so a second run on the same day mostly re-reads the
page instead of repeating work. That is what makes an unattended schedule safe:
the worst a duplicate run costs you is time.

The browser runs against a real profile directory under `data-dir/`, so the
sign-in is a normal Microsoft sign-in performed once, by hand. Rewards is
per-account and the profile holds the sign-in, which is also what makes
[multi-account](#running-more-than-one-account) work.

Search strings come from one of two backends, chosen with `QUERY_SOURCE`. The
default in this fork, `trends`, needs no account, no API key and no model
download. The original `llm` backend, which talks to OpenRouter or a local
OpenAI-compatible endpoint, is still there and unchanged.

---

## Key Features

| Feature | Description |
|---|---|
| **Idempotent Tasks** | Every task checks its own completion first, so re-running is cheap and safe rather than a source of duplicate work. |
| **Once-A-Day Guard** | `scripts/run_daily.sh` will not open a browser at all once the day's work is done, and a failed run is never marked as done. |
| **Headless Scheduling** | Runs without a display, so it works on a machine nobody is logged in at. systemd, Task Scheduler and launchd are all wired up. |
| **Two Attempts A Day** | A morning slot, plus an evening retry for the two cases that matter: the morning failed, or the machine was asleep. The guard makes the second a no-op on a good day. |
| **Trend-Based Queries** | Search strings from Google Trends RSS, Wikipedia's most-read feed and Bing autosuggest. No API key, no model, no account. |
| **LLM Queries** | The original backend, via OpenRouter or any OpenAI-compatible local endpoint. |
| **Multi-Account** | `REWARDS_ACCOUNTS` runs several profile directories in sequence; a failing one is reported and skipped, not fatal. |
| **Docker Path** | Runs the bot with no Edge, driver or Python on the host, and signs in through a browser-in-a-container. |
| **Virtual Desktop** | On Windows, run the browser on a separate virtual desktop so the run stays out of your way. |
| **Driver Diagnostics** | Names the likely cause when Edge fails to start, with an optional verbose `msedgedriver` log. |

---

## Daily Scheduling

The bot is safe to re-run but an unattended schedule should not re-run it, so
`scripts/run_daily.sh` puts a cheap guard around the whole thing:

- **At most one run at a time.** A lock file, so a scheduled run that collides
  with a manual one does not fight it over the browser profile.
- **No browser after success.** A dated marker records the day. Once it exists,
  the run exits before launching anything.
- **Never marks a failure as success.** The marker is written only on a clean
  exit, so a crashed run is retried by the next slot.
- **Headless, always.** `REWARDS_HEADLESS=true` is forced for the scheduled run.

Run it by hand whenever you like — it is safe to do so:

```sh
./scripts/run_daily.sh
```

### Linux (systemd)

The installer registers this for you and writes the unit with your checkout's
real path already filled in. To do it by hand, substitute your own path in place
of `REPO_DIR_PLACEHOLDER`:

```sh
mkdir -p ~/.config/systemd/user
sed "s|REPO_DIR_PLACEHOLDER|$PWD|g" scripts/systemd/rewards-farmer.service \
  > ~/.config/systemd/user/rewards-farmer.service
cp scripts/systemd/rewards-farmer.timer ~/.config/systemd/user/

# Survive logout, so the timer keeps working with nobody signed in
sudo loginctl enable-linger "$USER"

systemctl --user daemon-reload
systemctl --user enable --now rewards-farmer.timer

# Check it is armed
systemctl --user list-timers rewards-farmer.timer
```

The `Environment=` lines in the unit pin Edge and the driver so the timer does
not depend on your login shell's `PATH`. Fill them in if you know where they
are, or delete both lines: Selenium Manager finds both on its own, and a path
pinned to a binary that has since moved is worse than no pin at all.

`Persistent=true` means a slot missed because the machine was off fires on next
login instead of being silently skipped.

### Windows (Task Scheduler)

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-ExecutionPolicy Bypass -File "C:\rewards-farmer\scripts\windows\run-daily.ps1"'

$triggers = @(
  New-ScheduledTaskTrigger -Daily -At 8:00am
  New-ScheduledTaskTrigger -Daily -At 8:00pm
)

Register-ScheduledTask -TaskName 'RewardsFarmer' -Action $action -Trigger $triggers `
  -Description 'Microsoft Rewards farmer, at most once a day'
```

The script is headless, so it needs no interactive session — but Task Scheduler
still defaults to *run only when the user is logged on*, and it cannot run while
nobody is logged in unless you store a password for the account. That is fine on
a desktop that is on at 08:00; for an always-on machine, use the container
below and schedule that instead.

### macOS (launchd)

```sh
mkdir -p ~/Library/LaunchAgents ~/Library/Logs/rewards-farmer   # launchd opens the logs before the script runs

sed -e "s|REPO_DIR_PLACEHOLDER|$PWD|g" \
    -e "s|HOME_PLACEHOLDER|$HOME|g" \
    scripts/macos/com.g4zwr.rewards-farmer.plist \
    ~/Library/LaunchAgents/com.g4zwr.rewards-farmer.plist

launchctl load ~/Library/LaunchAgents/com.g4zwr.rewards-farmer.plist
launchctl list | grep rewards-farmer
```

The installer performs exactly those substitutions, so this is only needed if
you set the schedule up yourself. Unload it again with the same command and
`unload` in place of `load`.

`launchd` runs jobs with almost no environment, which is why the plist states
`PATH` and `HOME` explicitly.

### Logs and state

State lives in one place per platform, all of it outside the repository, so
`git status` stays clean and nothing is ever committed by accident:

| Platform | Location |
|---|---|
| Linux / macOS | `~/.local/state/rewards-farmer/` |
| Windows | `%LOCALAPPDATA%\rewards-farmer\` |

Each holds `last-success-YYYY-MM-DD`, the lock, and `logs/run-YYYY-MM-DD.log`
with the full output of the run. To force a run, delete today's marker.

> **On macOS, note that `flock` is not part of the base system.** The script
> uses it when it is there and falls back to an atomic `mkdir` for its lock when
> it is not, so it runs unmodified on a stock Mac.

---

## Configuration

Everything is read from `.env` in the project root; see
[`.env.example`](.env.example) for the full list. `main.py` loads it with
python-dotenv's default `override=False`, so a real environment variable beats
the file — which is how the scheduler forces headless mode over a
`REWARDS_HEADLESS=false` sitting in `.env`.

### Where search queries come from

The bot needs short strings to type into Bing. Two backends produce them, set
with `QUERY_SOURCE`:

| `QUERY_SOURCE` | Needs | Notes |
| --- | --- | --- |
| `llm` (original default) | OpenRouter or Ollama account + model | The project's original behaviour, unchanged |
| `trends` | nothing | Google Trends, Wikipedia and Bing autosuggest |

```sh
QUERY_SOURCE=trends python src/main.py          # bash
$env:QUERY_SOURCE="trends"; python src/main.py  # PowerShell
```

`trends` needs no account, no API key and no model download, so the LLM setup
below is optional. If every feed is unreachable it falls back to `nouns.txt`
rather than failing the run — edit that file to add or replace the seed words,
one per line.

For `llm`, set a provider in `.env`:

```env
LLM_PROVIDER=openrouter
OPENROUTER_API_KEY=your_key_here
OPENROUTER_MODEL=openai/gpt-4o-mini

# Or use a local endpoint instead
# LLM_PROVIDER=local
# LOCAL_LLM_BASE_URL=http://localhost:11434/v1
# LOCAL_LLM_MODEL=gemma3:4b
```

OpenRouter is used through the OpenAI-compatible chat completions API at
`https://openrouter.ai/api/chat/completions`; a local endpoint must speak the
same shape. With no configuration at all, the defaults are
`LLM_PROVIDER=local`, `LOCAL_LLM_BASE_URL=http://localhost:11434/v1`,
`LOCAL_LLM_MODEL=gemma4:cloud` and `OPENROUTER_MODEL=openrouter/free`.

### The visual search image

The script needs an image to upload for the visual search task. Generate one
with the included helper, which downloads a Wikipedia image as
`visual_search.jpg` into the project root:

```sh
python src/random_image_for_visual_search.py
```

To use your own instead, put its absolute path in the `VISUAL_SEARCH_IMAGE_PATH`
constant at the top of `rewards_tasks.py`.

### Profile setup

The profile directory in `src/constants.py` is set to `Default`. If that signs
you in to a global profile you would rather not automate, create a new profile
from within the webdriver instance by hand and set `PROFILE_NAME` to `Profile 1`
(or the equivalent number).

Run `python src/main.py`, wait for the page to launch, then `Ctrl-C` to quit
immediately. Sign in to the created profile with your Microsoft account on both
Bing and `rewards.bing.com`. Close every webdriver browser instance, run
`main.py` again, and the automation should start working.

**EU users:** you may have to accept a consent banner once on `rewards.bing.com`
and on `bing.com`. Once you consent, the choice is saved for later runs on the
same profile, so you will not meet it during automated runs.

---

## Docker

Runs the bot without installing Edge, a driver or Python on the host.

```sh
docker compose build
docker compose run --rm rewards-farmer
```

The container defaults to `QUERY_SOURCE=trends`, so it needs no Ollama account
and no model. Set `QUERY_SOURCE=llm` and `OLLAMA_HOST` to a reachable address to
use a model instead.

**Sign in first.** The profile in `data-dir` starts logged out. Sign in from
inside the container, which opens the Rewards page in a browser there and puts
that browser on your screen as a web page:

```sh
docker compose run --rm --service-ports signin
```

Open <http://localhost:6080>, sign in, then close the Edge window on that
screen. The container exits on its own and the profile is ready. Nothing is
installed on the host, and the host OS stops mattering, because the profile is
written inside the container rather than on the host. The screen is an ordinary
web page, so whatever browser you already have will do.

`--service-ports` is not optional. `docker compose run` publishes no ports
without it, and the page then never loads — which reads as a broken feature
rather than a missing flag.

One account at a time, since it is one browser window:

```sh
REWARDS_ACCOUNTS=personal docker compose run --rm --service-ports signin
```

The port is published on `127.0.0.1` only, so it is not reachable from the
network. While the service is up it is showing a live Microsoft sign-in page.

Signing in signs the *browser* in, not just the website, so Edge may sync
bookmarks and autofill into the profile it just created. `data-dir` is a bot
profile living in the project directory rather than your everyday browser
profile, and it is gitignored, but it is worth knowing what ends up there.

<details>
<summary><strong>Why sign-in has to happen inside the container</strong></summary>

Chromium encrypts cookie values with a key it gets from the operating system,
and the container has to be able to unwrap that key to read the profile.

On **Linux** with no keyring running it falls back to a fixed key, which is true
both on a plain Linux host and inside the image, so a profile signed in on such
a host does carry straight in.

On **Windows** the key is wrapped with DPAPI and tied to the Windows account
that wrote it, and the container has no DPAPI. A profile signed in with a
normal Windows Edge window reported 73 cookies on disk, of which Edge in the
container could read 19 — the ones it had just set itself — while `.MSA.Auth`
and `ANON`, the ones the sign-in actually rests on, came back absent. The
container starts, looks healthy and behaves as though it were logged out.
**macOS** wraps the key with the login Keychain, which the container cannot
reach either.

Signing in through the container sidesteps all of this: the profile is written
by the same Edge that later reads it, so the two never disagree about the key.

</details>

You can still sign in with a host browser if you prefer, and on a Linux host it
works. Close every window of that profile afterwards, and close them rather
than killing them: Chromium allows one process per profile directory, and a
browser that was killed leaves a `SingletonLock` naming the machine that wrote
it, which the container reads as the profile being open somewhere else.

**Provide the visual search image on the host too.** `visual_search.jpg` is not
in the repository and is not built into the image, so create it once in the
project root and the compose file mounts it in:

```sh
python src/random_image_for_visual_search.py
```

Without it every other task still runs; only the visual search one fails.

Multiple accounts work the same way in the container. Sign each profile in once,
one at a time, then run them together:

```sh
REWARDS_ACCOUNTS=personal docker compose run --rm --service-ports signin
REWARDS_ACCOUNTS=spare    docker compose run --rm --service-ports signin

REWARDS_ACCOUNTS=personal,spare docker compose run --rm rewards-farmer
```

`REWARDS_HEADLESS=1` is set in the image. It also works on the host if you want
a run with no visible window. `src/browser.py` pins `--window-size=1920,1080` in
that mode, because the pointer code works in viewport coordinates and the
default headless window is small enough to put cards out of reach.

---

## Running more than one account

Rewards is per Microsoft account and the browser profile holds the sign-in, so
an account here is a profile directory. `REWARDS_ACCOUNTS` takes a comma
separated list, and each name gets its own directory under `data-dir`:

```sh
REWARDS_ACCOUNTS=personal,spare python src/main.py
```

Each is signed in once by hand, the same way as the single profile, using its
own directory:

```text
msedge --user-data-dir="<repo>\data-dir\personal" --profile-directory=Default https://rewards.bing.com
```

They run one after another, and an account that fails is reported and skipped
rather than ending the run, whether it fails to start or dies partway through.
Leave `REWARDS_ACCOUNTS` unset and everything behaves exactly as before, using
the single profile in `data-dir`.

---

## If Edge will not start

When the browser fails to start, the log names the likely cause from the
driver's own message, and falls back to printing that message as is. Three
optional environment variables help when it does not:

| Variable | Effect |
| --- | --- |
| `MSEDGEDRIVER_PATH` | Full path to `msedgedriver` to use, instead of letting selenium look for one. Try this first on *Unable to obtain driver for MicrosoftEdge*. |
| `EDGE_BINARY` | Full path to the Edge executable, for an install selenium does not find on its own. |
| `REWARDS_DRIVER_LOG` | Path to write a verbose msedgedriver log to. On *Chrome instance exited* this log holds Edge's actual reason; attach it to a bug report. |

```sh
$env:REWARDS_DRIVER_LOG="msedgedriver.log"; python src/main.py   # PowerShell
REWARDS_DRIVER_LOG=msedgedriver.log python src/main.py          # bash
```

`src/check_selectors.py` starts Edge the same way and reads the same variables.

The Edge and `msedgedriver` versions must match exactly. A mismatched pair is
the most common cause of a driver that connects and then immediately drops.

---

## Logging

The script logs to the console. Two optional environment variables change that:

| Variable | Default | Effect |
| --- | --- | --- |
| `REWARDS_FARMER_LOG_LEVEL` | `INFO` | Set to `DEBUG` to also attach the full stack trace to every `[FAIL]` line. |
| `REWARDS_FARMER_LOG_FILE` | unset | Path to also write the log to, useful for unattended runs. |

```sh
REWARDS_FARMER_LOG_LEVEL=DEBUG REWARDS_FARMER_LOG_FILE=run.log python src/main.py   # bash
$env:REWARDS_FARMER_LOG_LEVEL="DEBUG"; $env:REWARDS_FARMER_LOG_FILE="run.log"; python src/main.py   # PowerShell
```

If you are opening an issue about a crash, running with
`REWARDS_FARMER_LOG_LEVEL=DEBUG` and attaching the log is the most useful thing
you can include.

---

## Windows Virtual Desktop

To run the browser on a separate Windows Virtual Desktop so searches run in the
background without interrupting your current workspace:

| Variable | Default | Effect |
| --- | --- | --- |
| `USE_VIRTUAL_DESKTOP` | `false` | When `true`, automatically creates a new Windows Virtual Desktop via `Win+Ctrl+D` and launches the browser there. Windows only. |
| `SWITCH_BACK_TO_MAIN_DESKTOP` | `true` | When `true` (and `USE_VIRTUAL_DESKTOP` is enabled), automatically switches back to your starting desktop after launching Edge. |
| `SWITCH_BACK_DELAY_SECONDS` | `1.5` | Delay in seconds to wait before switching back, giving Edge time to attach its window to the new desktop. |
| `CLEANUP_VIRTUAL_DESKTOP` | `true` | When `true`, automatically closes the created worker virtual desktop via `Win+Ctrl+F4` after completing all profiles and pressing Enter, returning focus to your main desktop. |

```powershell
$env:USE_VIRTUAL_DESKTOP="true"; python src/main.py
```

> **Note:** The script detects which virtual desktop you started from and
> calculates the exact number of navigation hops so it returns directly to your
> starting desktop. When `CLEANUP_VIRTUAL_DESKTOP=true`, the worker desktop is
> safely closed after you press Enter on exit.

---

## Troubleshooting

**The scheduled run does nothing and prints "already ran today".**
Working as intended — the day's work is marked done. Delete
`last-success-YYYY-MM-DD` from the state directory to force a run.

**The scheduled run exits 0 but earned nothing.**
Check `logs/run-YYYY-MM-DD.log`. Exit `0` from `main.py` means the browser
started and the run finished; it does not mean every optional task completed.
`[SKIP]` lines are normal for tasks the account has no quota for.

**Everything reports `[FAIL]`.**
Run once by hand at `REWARDS_FARMER_LOG_LEVEL=DEBUG` and read the stack traces
it attaches to each failure. Visual search and Explore both depend on the
en-US Bing layout and are the first things to break when Microsoft changes a
page.

**A run hangs forever.**
Close it. The day is not marked, so the next slot tries again. Under systemd
this cannot outlive 30 minutes.

**`poetry env activate` says "Cannot bind argument to parameter 'Command'".**
See the note in the install section — it is a Python version problem, not a
poetry problem.

---

## Credits

This project would not exist without the original work. All credit for the
approach, the task set and the detection-avoidance techniques goes to:

- **[Carl Furtado (`User0332`)](https://github.com/User0332/rewards-farmer)** —
  the original author of `rewards-farmer`, and the
  [video](https://youtu.be/4qdPcMNaioA) it is built on.
- **[`ethanstoner/rewards-farmer`](https://github.com/ethanstoner/rewards-farmer)** —
  an upstream fork, credited for the multi-account and driver-diagnostics work
  carried forward here.

This fork by [`g4zwr`](https://github.com/g4zwr/rewards-farmer) adds the
cross-platform daily scheduler (`systemd`, Task Scheduler and `launchd`), a
headless `trends` query source that needs no account, the Docker sign-in
service, a more robust Visual Search selector, and this documentation.

Please open an issue if you run into any difficulties.

---

## License

MIT. See [`LICENSE`](LICENSE).
