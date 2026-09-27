#!/usr/bin/env bash
#
# Rewards Farmer installer for Linux and macOS.
#
# Brings a machine to the point where `python src/main.py` runs: a supported
# Python, a virtualenv, the project dependencies, Microsoft Edge and the two
# files the bot expects to find. Nothing here is installed silently -- any step
# that changes the machine prints the exact command first and waits for a yes.
#
#   ./install.sh              install, asking before each system change
#   ./install.sh -y           install, answering yes to everything
#   ./install.sh --no-edge    skip the Edge check entirely
#   ./install.sh --no-schedule  do not offer to install the scheduler
#   ./install.sh --dir PATH   install into PATH, cloning it if it is not a repo
#
set -euo pipefail

REPO_URL="${REWARDS_FARMER_REPO_URL:-https://github.com/g4zwr/rewards-farmer.git}"
REPO_BRANCH="${REWARDS_FARMER_REPO_BRANCH:-main}"
REPO_NAME="rewards-farmer"

# Oldest Python the project supports (must match requires-python in pyproject).
PY_MIN_MINOR=12
# Only used on macOS with no Homebrew, where there is no package manager to ask.
PY_FALLBACK_VERSION="3.12.8"
PY_PKG_URL="https://www.python.org/ftp/python/${PY_FALLBACK_VERSION}/python-${PY_FALLBACK_VERSION}-macos11.pkg"

ASSUME_YES=0
WANT_EDGE=1
WANT_SCHEDULE=1
TARGET_DIR=""

# ---------------------------------------------------------------- output ----

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
	C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
else
	C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BLUE" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '    %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
dim()  { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Ask before doing anything that changes the machine. Prints the command it is
# about to run so the answer is an informed one.
confirm() {
	local prompt="$1"
	if [ "$ASSUME_YES" -eq 1 ]; then
		info "$prompt ${C_DIM}(yes, -y)${C_RESET}"
		return 0
	fi
	if [ ! -t 0 ]; then
		warn "$prompt"
		dim "Not a terminal, so not asking. Re-run with -y to allow it."
		return 1
	fi
	local reply
	printf '    %s [y/N] ' "$prompt"
	read -r reply || return 1
	case "$reply" in
		[yY] | [yY][eE][sS]) return 0 ;;
		*) return 1 ;;
	esac
}

run() {
	printf '    %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
	"$@"
}

# ------------------------------------------------------------------ args ----

usage() {
	sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
		-y | --yes)         ASSUME_YES=1 ;;
		--no-edge)          WANT_EDGE=0 ;;
		--no-schedule)      WANT_SCHEDULE=0 ;;
		--dir)              [ $# -ge 2 ] || die "--dir needs a path"; TARGET_DIR="$2"; shift ;;
		--dir=*)            TARGET_DIR="${1#*=}" ;;
		-h | --help)        usage; exit 0 ;;
		*)                  die "Unknown option: $1 (try --help)" ;;
	esac
	shift
done

# ------------------------------------------------------------- platform ----

PLATFORM="$(uname -s)"
case "$PLATFORM" in
	Linux)  PLATFORM="linux" ;;
	Darwin) PLATFORM="macos" ;;
	*)      die "Unsupported platform: $PLATFORM. On Windows, run install.bat instead." ;;
esac

DISTRO_ID=""
DISTRO_FAMILY=""
if [ "$PLATFORM" = "linux" ]; then
	if [ -r /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		DISTRO_ID="${ID:-unknown}"
		DISTRO_FAMILY="$DISTRO_ID"
		case "$DISTRO_ID" in
			ubuntu | debian | linuxmint | pop | elementary | kali | raspbian | zorin)
				DISTRO_FAMILY="debian" ;;
			arch | archarm | manjaro | endeavouros | garuda)
				DISTRO_FAMILY="arch" ;;
			fedora | rhel | centos | rocky | almalinux | ol)
				DISTRO_FAMILY="fedora" ;;
			opensuse* | sles | suse)
				DISTRO_FAMILY="suse" ;;
		esac
	fi
fi

# ---------------------------------------------------------- locate repo ----

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Already inside a clone? Then work in place, no network needed.
if [ -f "$SCRIPT_DIR/pyproject.toml" ] && [ -d "$SCRIPT_DIR/src" ]; then
	REPO_DIR="$SCRIPT_DIR"
	NEEDS_CLONE=0
else
	REPO_DIR="${TARGET_DIR:-$SCRIPT_DIR/$REPO_NAME}"
	NEEDS_CLONE=1
fi

step "Rewards Farmer installer"
info "platform   $PLATFORM${DISTRO_ID:+ ($DISTRO_ID)}"
info "target     $REPO_DIR"

if [ "$NEEDS_CLONE" -eq 1 ]; then
	have git || die "git is required to download the project. Install git, or clone the repo yourself and run install.sh from inside it."
	step "Downloading the project"
	if [ -d "$REPO_DIR/.git" ]; then
		run git -C "$REPO_DIR" fetch --quiet origin "$REPO_BRANCH"
		run git -C "$REPO_DIR" checkout --quiet "$REPO_BRANCH"
		ok "updated to $REPO_BRANCH"
	else
		run git clone --quiet --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
		ok "cloned $REPO_BRANCH"
	fi
fi

[ -f "$REPO_DIR/pyproject.toml" ] || die "No pyproject.toml in $REPO_DIR - is this the right directory?"
cd "$REPO_DIR"

# --------------------------------------------------------------- python ----

python_ok() {
	# Interpolated from PY_MIN_MINOR so the minimum is written down once, which
	# is what installer-lint.yml checks against pyproject.toml.
	"$1" -c "import sys; raise SystemExit(0 if sys.version_info >= (3, $PY_MIN_MINOR) else 1)" >/dev/null 2>&1
}

find_python() {
	local candidate resolved
	# python3.$PY_MIN_MINOR is checked explicitly because Homebrew's
	# python@3.12 installs python3.12 and leaves python3 and python absent, so
	# without it a successful brew install would still be reported as missing.
	for candidate in python3.13 "python3.$PY_MIN_MINOR" python3 python; do
		have "$candidate" || continue
		resolved="$(command -v "$candidate")"
		if python_ok "$resolved"; then
			printf '%s' "$resolved"
			return 0
		fi
	done
	return 1
}

python_install_hint() {
	if [ "$PLATFORM" = "macos" ]; then
		if have brew; then
			printf 'brew install python@3.%s' "$PY_MIN_MINOR"
		else
			printf 'curl -fsSL -o python-installer.pkg %s && sudo installer -pkg python-installer.pkg -target /' "$PY_PKG_URL"
		fi
		return 0
	fi

	case "$DISTRO_FAMILY" in
		arch)   printf 'sudo pacman -S --needed --noconfirm python' ;;
		debian) printf 'sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip' ;;
		fedora) printf 'sudo dnf install -y python3 python3-pip' ;;
		suse)   printf 'sudo zypper --non-interactive install python3 python3-pip' ;;
		*)      return 1 ;;
	esac
}

step "Checking Python"
PYTHON=""
if PYTHON="$(find_python)"; then
	ok "$("$PYTHON" -c 'import sys; print("Python " + sys.version.split()[0])') ($PYTHON)"
else
	warn "No Python ${PY_MIN_MINOR}+ found."
	if ! HINT="$(python_install_hint)"; then
		die "Unsupported distribution '${DISTRO_ID:-unknown}'. Install Python ${PY_MIN_MINOR}+ yourself, then re-run this script."
	fi
	info "This would run:"
	dim "    $HINT"
	if ! confirm "Install Python ${PY_MIN_MINOR}+ now?"; then
		die "Python ${PY_MIN_MINOR}+ is required. Install it, then re-run this script."
	fi
	# Intentional word splitting: the hint is a command line, not an argument.
	# shellcheck disable=SC2086
	if ! eval "$HINT"; then
		die "Python installation failed. Install Python ${PY_MIN_MINOR}+ manually, then re-run."
	fi
	# A fresh Homebrew install is not on PATH in the shell that installed it.
	if [ "$PLATFORM" = "macos" ] && [ -d /opt/homebrew/bin ]; then
		export PATH="/opt/homebrew/bin:$PATH"
	fi
	PYTHON="$(find_python)" || die "Python ${PY_MIN_MINOR}+ still not on PATH after installing. Open a new shell and re-run."
	ok "$("$PYTHON" -c 'import sys; print("Python " + sys.version.split()[0])') installed"
fi

# ------------------------------------------------------------ virtualenv ----

step "Setting up the virtualenv"
[ -d .venv ] && info "reusing existing .venv"
if [ ! -d .venv ]; then
	run "$PYTHON" -m venv .venv || die "Could not create .venv. On Debian/Ubuntu install python3-venv."
fi
VENV_PY="$REPO_DIR/.venv/bin/python"
[ -x "$VENV_PY" ] || die "No interpreter at $VENV_PY"
ok "using $("$VENV_PY" -c 'import sys; print("Python " + sys.version.split()[0])') in .venv"

# Read the dependency list straight out of pyproject.toml so this script cannot
# drift from it. tomllib is in the standard library from 3.11.
step "Installing dependencies"
"$VENV_PY" - <<'PY' > .requirements.tmp
import tomllib
with open("pyproject.toml", "rb") as handle:
    project = tomllib.load(handle)["project"]
print("\n".join(dep.replace(" (", "(").replace(" )", ")") for dep in project["dependencies"]))
PY
DEPCOUNT="$(wc -l < .requirements.tmp | tr -d ' ')"
info "$DEPCOUNT dependencies from pyproject.toml"
if run "$VENV_PY" -m pip install --quiet --upgrade pip; then :; else warn "could not upgrade pip; continuing"; fi
run "$VENV_PY" -m pip install --quiet -r .requirements.tmp || die "Dependency installation failed."
rm -f .requirements.tmp
ok "dependencies installed"

# ------------------------------------------------------------------ edge ----

edge_present() {
	if [ "$PLATFORM" = "macos" ]; then
		[ -d "/Applications/Microsoft Edge.app" ] && return 0
		have "Microsoft Edge" && return 0
		return 1
	fi
	local candidate
	for candidate in microsoft-edge-stable microsoft-edge microsoft-edge-dev microsoft-edge-beta; do
		have "$candidate" && return 0
	done
	[ -x /usr/bin/microsoft-edge-stable ] && return 0
	[ -x /opt/microsoft/msedge/msedge ] && return 0
	return 1
}

edge_install_hint() {
	if [ "$PLATFORM" = "macos" ]; then
		have brew || return 1
		printf 'brew install --cask microsoft-edge'
		return 0
	fi
	case "$DISTRO_FAMILY" in
		arch)
			# Not in Arch's official repositories; the -bin variant is the AUR one.
			# Any AUR helper will do, and all of them understand the same flags.
			if have yay; then printf 'yay -S --noconfirm --needed microsoft-edge-stable-bin'
			elif have paru; then printf 'paru -S --noconfirm --needed microsoft-edge-stable-bin'
			else
				# No AUR helper, so say what to do rather than nothing. Naming the
				# package is what the user needs; the helper is their choice.
				printf 'install an AUR helper (yay or paru), then: yay -S --needed microsoft-edge-stable-bin'
			fi
			;;
		debian)
			printf 'curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list >/dev/null && sudo apt-get update && sudo apt-get install -y microsoft-edge-stable'
			;;
		fedora)
			printf 'sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/edge/config.repo && sudo dnf install -y microsoft-edge-stable'
			;;
		*) return 1 ;;
	esac
}

EDGE_OK=0
if [ "$WANT_EDGE" -eq 0 ]; then
	step "Microsoft Edge"
	dim "skipped (--no-edge)"
elif edge_present; then
	step "Microsoft Edge"
	ok "already installed"
	EDGE_OK=1
else
	step "Microsoft Edge"
	warn "not found - the bot drives a real Edge, so this one is required."
	if HINT="$(edge_install_hint)"; then
		info "This would run:"
		dim "    $HINT"
		if confirm "Install Edge now?"; then
			# shellcheck disable=SC2086
			if eval "$HINT"; then
			if edge_present; then
				EDGE_OK=1
				ok "installed"
			else
				warn "installed, but not on PATH yet - restart your shell"
			fi
			else
				warn "Edge installation failed"
			fi
		else
			warn "skipped"
		fi
	else
		dim "No automatic install known for this platform. See the README for the manual step."
	fi
	[ "$EDGE_OK" -eq 0 ] && dim "Everything else is ready; only Edge is still missing."
fi

# ------------------------------------------------------- project files ----

step "Project files"

# The bot uploads this image for the visual search task. It is gitignored
# because it is a downloaded binary, not source.
if [ -f visual_search.jpg ]; then
	ok "visual_search.jpg already present"
elif run "$VENV_PY" src/random_image_for_visual_search.py; then
	ok "generated visual_search.jpg"
else
	warn "could not generate visual_search.jpg - only the visual search task needs it"
fi

if [ -f .env ]; then
	ok ".env already present (left alone)"
else
	cp .env.example .env
	ok "created .env from .env.example"
fi

# ------------------------------------------------------------- schedule ----

# Where the browser actually is, so the schedule can pin it. A timer gets a much
# smaller environment than a login shell, but a *wrong* pinned path is worse
# than none: Selenium trusts EDGE_BINARY over its own search, so a stale value
# here would break a run that would otherwise have worked. Both helpers fail
# rather than guess, and the caller then leaves the line out entirely.
edge_binary_path() {
	local candidate resolved
	for candidate in microsoft-edge-stable microsoft-edge microsoft-edge-beta microsoft-edge-dev; do
		resolved="$(command -v "$candidate" 2>/dev/null)" || continue
		if [ -x "$resolved" ]; then
			printf '%s' "$resolved"
			return 0
		fi
	done
	return 1
}

driver_binary_path() {
	local candidate resolved
	resolved="$(command -v msedgedriver 2>/dev/null)" || resolved=""
	if [ -n "$resolved" ] && [ -x "$resolved" ]; then
		printf '%s' "$resolved"
		return 0
	fi
	# Selenium Manager downloads its own driver, so the usual install location
	# is checked only to save it the trouble.
	for candidate in /usr/local/bin/msedgedriver /usr/bin/msedgedriver "$HOME/bin/msedgedriver"; do
		if [ -x "$candidate" ]; then
			printf '%s' "$candidate"
			return 0
		fi
	done
	return 1
}

# Fill in a scheduler template. The templates ship with placeholders so they stay
# honest in the repo; this substitutes the real clone location, so a project that
# does not live in ~/rewards-farmer still gets a working schedule. Done in Python
# rather than sed because a path may legally contain & or |, which sed would
# misread, and because the virtualenv is already known to work at this point.
#
# Arguments: template, destination, edge path or -, driver path or -.
render_schedule_template() {
	local template="$1" destination="$2" edge="${3:--}" driver="${4:--}"
	"$VENV_PY" - "$template" "$destination" "$edge" "$driver" <<'PY'
import os
import sys

template, destination, edge, driver = sys.argv[1:5]
repo = os.getcwd()
home = os.path.expanduser("~")

text = open(template, encoding="utf-8").read()
text = text.replace("REPO_DIR_PLACEHOLDER", repo)
text = text.replace("HOME_PLACEHOLDER", home)

# An unresolved browser path means the binary was not found, so the whole line
# goes rather than shipping a placeholder into systemd.
out = []
for line in text.splitlines(keepends=True):
    if line.startswith("Environment=EDGE_BINARY="):
        if edge != "-":
            line = "Environment=EDGE_BINARY=" + edge + "\n"
        else:
            continue
    elif line.startswith("Environment=MSEDGEDRIVER_PATH="):
        if driver != "-":
            line = "Environment=MSEDGEDRIVER_PATH=" + driver + "\n"
        else:
            continue
    out.append(line)

with open(destination, "w", encoding="utf-8") as handle:
    handle.write("".join(out))
PY
}

SCHEDULED=0
if [ "$WANT_SCHEDULE" -eq 0 ]; then
	step "Daily schedule"
	dim "skipped (--no-schedule)"
elif [ "$PLATFORM" = "macos" ]; then
	step "Daily schedule"
	PLIST_SRC="scripts/macos/com.g4zwr.rewards-farmer.plist"
	if [ ! -f "$PLIST_SRC" ]; then
		warn "missing $PLIST_SRC"
	elif ! have launchctl; then
		warn "launchctl not found - skipping"
	elif confirm "Install the launchd agent (runs at 08:00 and 20:00)?"; then
		AGENT_DIR="$HOME/Library/LaunchAgents"
		AGENT="$AGENT_DIR/com.g4zwr.$REPO_NAME.plist"
		mkdir -p "$AGENT_DIR" "$HOME/Library/Logs/$REPO_NAME"
		# launchd opens the log files before the script starts, so the
		# directory has to exist first, which the mkdir above does.
		render_schedule_template "$PLIST_SRC" "$AGENT" "-" "-"
		dim "wrote $AGENT with the paths for this checkout"
		info "This would run:"
		dim "    launchctl load $AGENT"
		if launchctl load "$AGENT" 2>/dev/null; then
			ok "loaded $AGENT"
			SCHEDULED=1
		else
			warn "launchctl load failed - the file is written to $AGENT if you want to load it yourself"
		fi
	fi
else
	step "Daily schedule"
	if ! have systemctl; then
		dim "systemd not available - skipping. See the README for cron."
	elif [ ! -d "$HOME/.config/systemd/user" ] && [ ! -f "$PWD/scripts/systemd/rewards-farmer.timer" ]; then
		dim "systemd user units unavailable - skipping"
	elif confirm "Install the systemd user timer (runs at 08:00 and 20:00)?"; then
		UNIT_DIR="$HOME/.config/systemd/user"
		mkdir -p "$UNIT_DIR"
		EDGE_PATH="$(edge_binary_path || true)"
		DRIVER_PATH="$(driver_binary_path || true)"
		render_schedule_template \
			scripts/systemd/rewards-farmer.service \
			"$UNIT_DIR/rewards-farmer.service" \
			"$EDGE_PATH" "$DRIVER_PATH"
		# The timer is plain systemd that only names the service, so it is
		# copied as-is.
		cp scripts/systemd/rewards-farmer.timer "$UNIT_DIR/"
		ok "wrote the unit for $PWD"
		if [ -n "$EDGE_PATH" ]; then
			dim "    Edge:   $EDGE_PATH"
		else
			dim "    Edge:   left to Selenium to find"
		fi
		if [ -n "$DRIVER_PATH" ]; then
			dim "    driver: $DRIVER_PATH"
		else
			dim "    driver: left to Selenium Manager to fetch"
		fi
		info "This would run:"
		dim "    loginctl enable-linger $USER"
		dim "    systemctl --user daemon-reload"
		dim "    systemctl --user enable --now rewards-farmer.timer"
		if confirm "Enable lingering so it runs while you are logged out?"; then
			run loginctl enable-linger "$USER" || warn "could not enable lingering"
		fi
		run systemctl --user daemon-reload
		if run systemctl --user enable --now rewards-farmer.timer; then
			ok "timer enabled"
			SCHEDULED=1
		else
			warn "could not enable the timer - the unit files are in $UNIT_DIR"
		fi
	fi
fi

# --------------------------------------------------------------- summary ----

step "Done"
if [ "$SCHEDULED" -eq 1 ]; then
	ok "installed, with a daily schedule"
elif [ "$WANT_SCHEDULE" -eq 1 ]; then
	ok "installed"
	dim "not scheduled - re-run with the scheduler, or see the README"
fi

cat <<EOF

    One thing left is manual, by design: signing in.

      $VENV_PY src/main.py

    A browser opens. Sign in to Bing and to rewards.bing.com, then press
    Ctrl-C. From then on it runs unattended:

      $VENV_PY src/main.py          # or ./scripts/run_daily.sh for the once-a-day guard

EOF

[ "$EDGE_OK" -eq 1 ] || warn "Microsoft Edge is still not installed - the bot will not start without it."
exit 0
