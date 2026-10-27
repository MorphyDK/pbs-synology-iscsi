#!/bin/bash
# =============================================================================
#   PBS Post-Install  ·  Proxmox Backup Server + Synology iSCSI
# =============================================================================
# Safe PBS post-install script with iSCSI setup, so you can back up via iSCSI
# to your Synology NAS.
# 
# Thanks to Derek Seaman's Tech Blog who inspired me to make this.
#
# Version 1.10.3  26/10-2026
# Author MorphyDK
#
# Usage:  ./pbs-post-install.sh              interactive installer
#         ./pbs-post-install.sh --status     health dashboard (no changes)
#         ./pbs-post-install.sh --fix-login  re-enter the CHAP login of an installed target
#         ./pbs-post-install.sh --add-drive  connect one more Synology LUN
#         ./pbs-post-install.sh --remove-drive  take a drive away again
#         ./pbs-post-install.sh --motd       install / update only the login screen
#         ./pbs-post-install.sh --motd-remove  remove the login screen again
#         ./pbs-post-install.sh --motd-update  silent update of the login screen, keeps settings
#         ./pbs-post-install.sh --help
#
# Changes in 1.10.3:
#  - The message shown when the installer is piped no longer suggests running it straight from
#    curl. Download, read, then run. No other change in behaviour
#
# Changes in 1.10.2:
#  - ShellCheck: the "unreachable" notes in the login screen are now really silenced (the
#    directive was placed after the first command in 1.10.1, where it did not cover the file)
#
# Changes in 1.10.1:
#  - ShellCheck clean-up: one unused variable in --status removed, and the login screen tells
#    ShellCheck that its screens are started through the pager (no more "unreachable" notes).
#    No change in behaviour
#
# Changes in 1.10.0:
#  - New: Drives submenu in pbs-menu (item 2): Drive details, Add a drive, Change the CHAP login,
#    Remove a drive
#  - New: --add-drive - connect one more Synology LUN with its own mount path, datastore and monitor.
#    Only the drive questions are asked (no repository, upgrade, popup or login-screen steps)
#  - New: --remove-drive - takes a drive away in the safe order: refuses while a task runs on its
#    datastore, removes the datastore from PBS (the files stay on the LUN), stops the monitor,
#    unmounts, removes the fstab line (copy kept), removes the boot-order file, and logs out of the
#    target - but only when no other drive uses it. You must type the drive name to confirm.
#    It never erases data and never changes anything on the Synology
#  - Fixed: adding a drive whose name starts like an existing one (synology / synology2) could
#    remove the other drive's cron job
#  - Fixed: a drive set up earlier is no longer offered as a "stale record" when you add a second one
#
# Changes in 1.9.3:
#  - Fixed: in pbs-menu, a long screen (LUN & connection with two drives, the health check, the
#    monitor log, help) was cut off at the top - the first drive was missing. Long screens are now
#    shown page by page below the frozen header (space = next, b = back, q = done)
#
# Changes in 1.9.2:
#  - The menu (pbs-menu) has a new look: the logo and the status pill stay FROZEN at the top
#    (a slim header on a small terminal), and every menu and screen scrolls below it
#  - Drive cards at the top of the menu: a small drive icon per LUN with thin/thick, filesystem,
#    size, a usage bar, free space and connection status
#  - The menu items are grouped (Watch, Check, System, Other) in a grid you move through with the
#    arrow keys; every item has a shortcut (number or letter). Badges show what needs attention:
#    updates waiting, a new installer, PBS stopped, a drive with a problem
#  - Fixed: items 10-12 of the old menu were shifted one space, and could not be jumped to
#  - ShellCheck clean-up: unused variables removed, a few lines rewritten. No change in behaviour
#
# Changes in 1.9.1:
#  - The reads/writes graph only uses characters that every terminal font has (· ░ ▒ ▓ █).
#    Some fonts showed the thin block characters as empty boxes
#
# Changes in 1.9.0:
#  - SELF-UPDATE. Once a day the login screen looks on GitHub (one request to api.github.com)
#    for a newer release. When there is one it shows a sharp red "NEW VERSION" line, and one key
#    (i at login, in the live dashboard, or pbs-menu > Installer update) installs it:
#    download -> syntax/size/version check -> the current version is saved -> installed ->
#    tested -> and put back automatically if anything fails. pbs-motd --rollback goes back by hand.
#    Only the login screen and this script are replaced; iSCSI, mounts and datastores are never touched.
#    Settings: turn the check off, or turn on automatic installation (off by default)
#  - Live dashboard: a third login style that stays open and refreshes until you press q, with a
#    key bar: m menu, l log, c repair, p page, h help, and u / i / r when an update, a new
#    installer or a reboot is waiting. Also: pbs-motd --live
#  - Live view: reads/writes per second as a small graph, plus the average latency to the NAS
#  - The login screen scripts are replaced with an atomic rename, so an update never rewrites a
#    file that is running
#
# Changes in 1.8.0:
#  - Login screen: an UPDATE ALERT. When packages can be upgraded the dashboard shows a sharp
#    red (blinking where the terminal supports it) "N UPDATE(S) AVAILABLE" line; kernel and core
#    updates are marked as needing a reboot
#  - Press u at login to install the updates (asks first, lists the packages, warns when
#    backups are running); s snoozes the question for 24 hours. Also in pbs-menu > System updates
#  - After an upgrade, or whenever a newer kernel is installed than the one running, a strong
#    "REBOOT RECOMMENDED" alert with a reboot question (press r at login)
#  - Fixed: the "updates available" count could stay old after you had upgraded. It is now
#    refreshed by an apt hook, and at login whenever apt or dpkg changed since
#  - Settings: the update question can be turned off (pbs-menu > Settings)
#
# Changes in 1.7.7:
#  - Detects thin vs thick LUNs (the disk reports it) and says so: the installer, --status and
#    the login screen show "LUN type". A thick LUN no longer claims "weekly TRIM gives space
#    back" (nothing can be given back); a thin LUN with space reclamation switched off in DSM
#    gets a warning with where to turn it on
#
# Changes in 1.7.6:
#  - Formatting is much faster on big LUNs: no block-by-block discard while creating the
#    filesystem (ext4 -E nodiscard, XFS -K). Space is given back to the Synology afterwards
#    by a TRIM that runs in the background, and weekly
#  - The spinner shows the real progress of mkfs ("progress 524288/13106688 (4%)")
#
# Changes in 1.7.5:
#  - Timers (the "Elapsed" line, the spinner, the final "completed in") use a monotonic clock.
#    Before, a clock correction by time sync in the middle of the install (common in VMs)
#    made them jump by minutes or hours
#
# Changes in 1.7.4:
#  - --status: a normal reconnect after a reboot no longer counts as a "problem event"
#
# Changes in 1.7.3:
#  - The progress spinner shows minutes:seconds, the last line the running command printed,
#    and a warning when it has been silent for 5 minutes (a stuck apt/dpkg is easy to spot)
#
# Changes in 1.7.2:
#  - Subscription popup: now uses the "NO NAG" method of the community-scripts
#    post-pbs-install script (apt hook /etc/apt/apt.conf.d/no-nag-script). The older patch
#    of this installer is removed automatically
#
# Changes in 1.7.1:
#  - Login screen right after a boot: it waits (max 25 s) for the Synology connection instead
#    of showing red "not connected" lines, starts the monitor once if needed, and shows only a
#    yellow note during the first minutes after boot
#  - A normal reconnect after a reboot no longer counts as a "problem event"

# Changes in 1.7:
#  - NEW login screen (MOTD): when you log in to the server you get a live dashboard with the
#    same look as the installer - server health, the Synology connection, mount, free space
#    (read live at every login), the monitor, services, running and last finished backup tasks
#  - NEW interactive menu (pbs-menu, or press m at login): live view, LUN details, storage,
#    full health check, "check & repair now", monitor log, services, help, settings
#  - NEW pbs-help: the key commands for iSCSI, storage and PBS on one page
#  - Enterprise repository is switched off before the first apt update (fixes the 401 error)
#
# Changes in 1.6.1 (fixes a bug found on a real system - Synology log:
#   "failed to login ... due to CHAP required but absent", once a minute):
#  - Re-running the installer while the LUN was still connected could overwrite the
#    stored CHAP username/password with EMPTY values. Stored logins are now detected and
#    kept (or re-asked); writing an empty login is blocked with a safety stop
#  - The monitor no longer retries a rejected login every minute: it logs the cause once,
#    waits 15 minutes between attempts (a wrong password every minute can lock the account)
#    and sends an alert
#  - Leftover iSCSI records (old tests, other portals) are listed by the installer and by
#    --status; ones that log in at boot without a valid CHAP login can be removed
#  - New --fix-login: type the CHAP login again for an installed target, test it, remount
#  - An existing record keeps its boot setting while the installer tests a login
#
# Changes in 1.6:
#  - Survives a Synology reboot/update: the iSCSI "replacement timeout" is raised
#    from 2 to 10 minutes, so the filesystem does not see I/O errors meanwhile
#  - Smarter monitor: write test, read-only / hung-storage detection and an
#    automatic repair (unmount > logout > login > mount) with a cooldown,
#    optional alerts (ntfy / webhook / email) and log rotation
#  - PBS now starts after the iSCSI mount (systemd drop-in; never blocks the web UI)
#  - LUN picker: a target with several LUNs shows a list instead of silently
#    using the first one; the chosen LUN is re-matched by WWN during the install
#  - New --status dashboard: session, mount, space, write test, TRIM, datastore,
#    monitor log. Exit code 1 if something is wrong (usable from cron / scripts)
#
# Changes in 1.5:
#  - Re-running on an already mounted LUN now corrects an outdated /etc/fstab line
#  - The iSCSI monitor uses timeouts, so a hanging login/mount can't block it

set -eE
export LC_ALL=C.UTF-8

VERSION="1.10.3"
LOG_FILE="/var/log/pbs-post-install.log"
FS_LABEL="pbs-data"
FOUR_TIB=4398046511104
# How long the kernel waits for a lost iSCSI connection before it reports I/O
# errors (open-iscsi default: 120). 600 = 10 minutes, enough for a DSM update.
REPLACEMENT_TIMEOUT=600
DS_CFG="${DS_CFG:-/etc/proxmox-backup/datastore.cfg}"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED=$'\e[1;31m'
GREEN=$'\e[1;32m'
YELLOW=$'\e[1;33m'
BLUE=$'\e[1;34m'
MAGENTA=$'\e[1;35m'
CYAN=$'\e[1;36m'
WHITE=$'\e[1;37m'
DIM=$'\e[2m'
BOLD=$'\e[1m'
NC=$'\e[0m'
# Readline-safe versions (so line editing in prompts does not get confused)
P_RED=$'\001'"$RED"$'\002'
P_CYAN=$'\001'"$CYAN"$'\002'
P_WHITE=$'\001'"$WHITE"$'\002'
P_DIM=$'\001'"$DIM"$'\002'
P_NC=$'\001'"$NC"$'\002'

if [[ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]]; then
    GRAD=($'\e[38;5;51m' $'\e[38;5;45m' $'\e[38;5;39m' $'\e[38;5;33m' $'\e[38;5;27m' $'\e[38;5;21m')
else
    GRAD=("$CYAN" "$CYAN" "$CYAN" "$BLUE" "$BLUE" "$BLUE")
fi
RULE=$(printf '━%.0s' $(seq 1 64))
PANEL_C="$BLUE"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
PHASE="setup"
INSTALL_STARTED=0
INSTALL_START=0
NEED_REBOOT=0
APT_UPDATED=0
APT_WARN=""
DO_REPO=1
DO_UPGRADE=1
DO_ISCSI=1
DO_DS=1
DO_NAG=1
DO_MOTD=1
ADD_DRIVE=0          # 1 = --add-drive: only connect another drive (no repo/upgrade/popup/login-screen steps)
MOTD_MODE="prompt"   # prompt | dashboard | live
GUIDE_DONE=0
declare -a NOTES=()
OS_CODENAME=""
OS_PRETTY=""
PBS_VERSION=""
HOST_IP=""
HOST_NAME=""
INITIATOR_IQN=""
REUSE_OK=""

PORTAL_IP=""
TARGET_IQN=""
CHAP_MODE=1
CHAP_USER=""
CHAP_PASS=""
declare -a DISCOVERED_TARGETS=()
declare -a NODES_CREATED=()
PROBE_SESSION=0
PROBE_TMP=""
LOGIN_RC=0

CHAP_KEEP=0          # 1 = keep the CHAP login already stored in the node record
NODE_PREEXISTED=0
declare -a KNOWN_NODES=()
NOTIFY_MODE="none"   # none | url | mail
NOTIFY_URL=""
NOTIFY_MAIL=""
SELF_CMD=""

DEVICE_PATH=""
declare -a LUN_DEVS=()
LUN_SIZE=""
LUN_SIZE_H=""
LUN_WWN=""
LUN_SERIAL=""
LUN_NUM=""
LUN_MODEL=""
LUN_DISCARD=0
LUN_PROV=""
LUN_EMPTY=0
LUN_LAYOUT=""
PROBE_NODE=""
PROBE_FS=""
PROBE_UUID=""
PROBE_OTHER=""
PROBE_MOUNTED_AT=""
PROBE_INSPECTED=0
PROBE_PBS=0
PROBE_PBS_SUB=""
PROBE_GROUPS=0
PROBE_LATEST=""
PROBE_USED=""
PROBE_FILES=0

DISK_ACTION=""      # new | format | keep | mounted
FS_TYPE="ext4"
MOUNT_PATH=""
DS_NAME=""
DS_PATH=""
DS_REUSE=0
DS_SKIP=0

PARTITION=""
UUID=""
FSTAB_ENTRY=""
ISCSI_SERVICE=""
CHECK_ISCSI_SCRIPT=""
BG_PID=""
RUN_RC=0
KEY=""
CURRENT_TASK="starting up"
CURRENT_STEP=-1

APT_ENV=(env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none)
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# ---------------------------------------------------------------------------
# Setup stepper + install checklist
# ---------------------------------------------------------------------------
SETUP_NAMES=("Welcome" "Options" "iSCSI tools" "Synology guide" "Connection" "LUN & filesystem" "Mount, datastore, extras" "Review")

STEP_NAMES=(
    "APT repositories"
    "System upgrade"
    "Connect to iSCSI target"
    "Prepare disk"
    "Mount via /etc/fstab"
    "Monitoring & boot order"
    "PBS datastore"
    "Subscription popup"
    "Login screen (MOTD)"
    "Finish"
)
S_REPO=0; S_UPG=1; S_CONN=2; S_DISK=3; S_MOUNT=4; S_MON=5; S_DS=6; S_NAG=7; S_MOTD=8; S_FIN=9
TOTAL_STEPS=${#STEP_NAMES[@]}
BAR_WIDTH=36
declare -a STEP_STATUS STEP_DETAIL
for (( _i = 0; _i < TOTAL_STEPS; _i++ )); do
    STEP_STATUS[_i]="pending"
    STEP_DETAIL[_i]=""
done

# ---------------------------------------------------------------------------
# Terminal helpers
# ---------------------------------------------------------------------------
hide_cursor() { if [[ -t 1 ]]; then printf '\e[?25l'; fi; }
show_cursor() { if [[ -t 1 ]]; then printf '\e[?25h'; fi; }

term_cols() {
    local c
    c=$(tput cols 2>/dev/null || echo 80)
    if ! [[ "$c" =~ ^[0-9]+$ ]]; then c=80; fi
    echo "$c"
}

term_rows() {
    local r
    r=$(tput lines 2>/dev/null || echo 24)
    if ! [[ "$r" =~ ^[0-9]+$ ]]; then r=24; fi
    echo "$r"
}

# Seconds from a monotonic clock (/proc/uptime). Bash's own $SECONDS follows the wall
# clock, so it jumps when time sync corrects the clock of a VM in the middle of the install.
MONO=0
mono() {
    local u
    read -r u _ < /proc/uptime || u=0
    MONO=${u%.*}
}

trunc() {
    local s="$1" w="$2"
    if (( w < 4 )); then w=4; fi
    if (( ${#s} > w )); then
        printf '%s…' "${s:0:w-1}"
    else
        printf '%s' "$s"
    fi
}

# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------
render_banner() {
    local i
    local -a art=(
        "██████╗ ██████╗ ███████╗"
        "██╔══██╗██╔══██╗██╔════╝"
        "██████╔╝██████╔╝███████╗"
        "██╔═══╝ ██╔══██╗╚════██║"
        "██║     ██████╔╝███████║"
        "╚═╝     ╚═════╝ ╚══════╝"
    )
    local -a side=(
        ""
        "${WHITE}Post-Install${NC}  ${DIM}v${VERSION}${NC}"
        "${CYAN}Proxmox Backup Server${NC}"
        "${DIM}+ Synology iSCSI LUN${NC}"
        "${DIM}by MorphyDK · based on Derek Seaman's guide${NC}"
        ""
    )
    echo
    for (( i = 0; i < 6; i++ )); do
        printf '   %s%s%s   %s\n' "${GRAD[i]}" "${art[i]}" "$NC" "${side[i]}"
    done
    echo "  ${CYAN}${RULE}${NC}"
}

render_header() {
    printf '\033[2J\033[H'
    echo "${CYAN}${RULE}${NC}"
    echo "  ${WHITE}PBS Post-Install${NC}  ${DIM}v${VERSION} · Proxmox Backup Server + Synology iSCSI${NC}"
    echo "${CYAN}${RULE}${NC}"
}

render_setup() {
    local idx="$1" i n dots=""
    n=${#SETUP_NAMES[@]}
    CURRENT_TASK="Setup: ${SETUP_NAMES[idx]}"
    render_header
    for (( i = 0; i < n; i++ )); do
        if (( i < idx )); then
            dots+="${GREEN}●${NC}"
        elif (( i == idx )); then
            dots+="${CYAN}◉${NC}"
        else
            dots+="${DIM}○${NC}"
        fi
        if (( i < n - 1 )); then
            dots+="${DIM}─${NC}"
        fi
    done
    echo
    printf '  %sSetup%s  %s  %sstep %d of %d%s\n' "$WHITE" "$NC" "$dots" "$DIM" $(( idx + 1 )) "$n" "$NC"
    printf '  %s%s%s%s\n\n' "$BOLD" "$CYAN" "${SETUP_NAMES[idx]}" "$NC"
}

count_done() {
    local n=0 s
    for s in "${STEP_STATUS[@]}"; do
        if [[ "$s" == "done" || "$s" == "skipped" ]]; then
            n=$(( n + 1 ))
        fi
    done
    echo "$n"
}

draw_bar() {
    local done_steps pct filled empty colour bar_full bar_empty
    done_steps=$(count_done)
    pct=$(( done_steps * 100 / TOTAL_STEPS ))
    filled=$(( done_steps * BAR_WIDTH / TOTAL_STEPS ))
    empty=$(( BAR_WIDTH - filled ))
    colour="$GREEN"
    if (( pct < 34 )); then
        colour="$RED"
    elif (( pct < 67 )); then
        colour="$YELLOW"
    fi
    bar_full=$(printf '%*s' "$filled" '' | sed 's/ /█/g')
    bar_empty=$(printf '%*s' "$empty" '' | sed 's/ /░/g')
    printf '  %sProgress%s %s[%s%s]%s %s%3d%%%s %s(%d/%d steps)%s\n' \
        "$WHITE" "$NC" "$colour" "$bar_full" "$bar_empty" "$NC" "$colour" "$pct" "$NC" "$DIM" "$done_steps" "$TOTAL_STEPS" "$NC"
}

render_screen() {
    local i icon colour el
    render_header
    echo
    draw_bar
    mono
    el=$(( MONO - INSTALL_START ))
    printf '  %sElapsed %02d:%02d%s\n\n' "$DIM" $(( el / 60 )) $(( el % 60 )) "$NC"
    for (( i = 0; i < TOTAL_STEPS; i++ )); do
        case "${STEP_STATUS[i]}" in
            done)    icon="✔"; colour="$GREEN" ;;
            running) icon="►"; colour="$CYAN" ;;
            skipped) icon="↷"; colour="$YELLOW" ;;
            failed)  icon="✘"; colour="$RED" ;;
            *)       icon="○"; colour="$DIM" ;;
        esac
        printf '  %s%s %-26s%s' "$colour" "$icon" "${STEP_NAMES[i]}" "$NC"
        if [[ -n "${STEP_DETAIL[i]}" ]]; then
            printf ' %s%s%s' "$DIM" "${STEP_DETAIL[i]}" "$NC"
        fi
        printf '\n'
    done
    echo
}

begin_step()  { CURRENT_STEP=$1; STEP_STATUS[$1]="running"; CURRENT_TASK="${STEP_NAMES[$1]}"; render_screen; }
finish_step() { STEP_STATUS[$1]="done"; STEP_DETAIL[$1]="${2:-}"; }
skip_step()   { STEP_STATUS[$1]="skipped"; STEP_DETAIL[$1]="${2:-skipped}"; }
fail_step()   { STEP_STATUS[$1]="failed"; STEP_DETAIL[$1]="${2:-}"; NOTES+=("${STEP_NAMES[$1]}: ${2:-failed}"); log_msg "FAIL  ${STEP_NAMES[$1]}: ${2:-}"; }

# ---------------------------------------------------------------------------
# Messages and panels
# ---------------------------------------------------------------------------
# Every message is also written to the log (without colours)
log_msg() {
    printf '%s  %s\n' "$(date '+%F %T')" "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null || true
}
# During the installation, warnings and errors are also collected for the finish screen
add_note() {
    if [[ "$PHASE" == "install" ]]; then
        NOTES+=("$*")
    fi
}
info()  { echo "  ${BLUE}ℹ${NC} $*"; log_msg "INFO  $*"; }
ok()    { echo "  ${GREEN}✔${NC} $*"; log_msg "OK    $*"; }
warn()  { echo "  ${YELLOW}⚠ $*${NC}"; log_msg "WARN  $*"; add_note "$*"; }
err()   { echo "  ${RED}✘ $*${NC}"; log_msg "ERROR $*"; add_note "$*"; }
note()  { echo "  ${BLUE}ℹ${NC} $*"; log_msg "NOTE  $*"; add_note "$*"; }
fatal() { show_cursor; log_msg "FATAL $*"; echo -e "\n  ${RED}✘ $*${NC}" >&2; echo "  ${DIM}Log: ${LOG_FILE}${NC}" >&2; exit 1; }

panel_top()    { PANEL_C="${2:-$BLUE}"; printf '  %s╭─%s %s%s%s\n' "$PANEL_C" "$NC" "$WHITE" "$1" "$NC"; }
panel_line()   { printf '  %s│%s %s\n' "$PANEL_C" "$NC" "$*"; }
panel_blank()  { printf '  %s│%s\n' "$PANEL_C" "$NC"; }
panel_bottom() { printf '  %s╰─%s\n' "$PANEL_C" "$NC"; PANEL_C="$BLUE"; }
kv()           { printf '  %s│%s %s%-14s%s %s\n' "$PANEL_C" "$NC" "$DIM" "$1" "$NC" "$2"; }

# ---------------------------------------------------------------------------
# Traps
# ---------------------------------------------------------------------------
cleanup() {
    local n
    show_cursor
    stty echo 2>/dev/null || true
    if [[ -n "$PROBE_TMP" ]]; then
        umount "$PROBE_TMP" >/dev/null 2>&1 || true
        rmdir "$PROBE_TMP" >/dev/null 2>&1 || true
    fi
    if [[ $INSTALL_STARTED -eq 0 ]]; then
        # Setup was cancelled: leave the system as we found it
        if [[ $PROBE_SESSION -eq 1 ]]; then
            iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" --logout >/dev/null 2>&1 || true
        fi
        for n in "${NODES_CREATED[@]}"; do
            iscsiadm -m node -T "${n%%|*}" -p "${n#*|}" -o delete >/dev/null 2>&1 || true
        done
    fi
}
trap cleanup EXIT

on_error() {
    show_cursor
    if [[ "$PHASE" == "install" && $CURRENT_STEP -ge 0 ]]; then
        STEP_STATUS[CURRENT_STEP]="failed"
    fi
    echo -e "\n  ${RED}✘ Script failed on line $1 during: ${CURRENT_TASK}${NC}" >&2
    echo "  ${DIM}Log: ${LOG_FILE}${NC}" >&2
}
trap 'on_error $LINENO' ERR

on_interrupt() {
    echo
    warn "Interrupted - waiting for the running task to finish safely..."
    if [[ -n "${BG_PID:-}" ]]; then
        wait "$BG_PID" 2>/dev/null || true
    fi
    echo "  ${YELLOW}Stopped by user.${NC}"
    exit 130
}
trap on_interrupt INT TERM

quit_clean() {
    show_cursor
    echo
    echo "  ${YELLOW}Setup cancelled - no disks were touched.${NC}"
    echo
    exit 0
}

# ---------------------------------------------------------------------------
# Input widgets
# ---------------------------------------------------------------------------
read_key() {
    local k="" rest=""
    IFS= read -rsn1 k || true
    if [[ "$k" == $'\e' ]]; then
        IFS= read -rsn2 -t 0.05 rest || true
        k+="$rest"
    fi
    case "$k" in
        $'\e[A'|$'\eOA'|k|K) KEY="up" ;;
        $'\e[B'|$'\eOB'|j|J) KEY="down" ;;
        "")                  KEY="enter" ;;
        " ")                 KEY="space" ;;
        [1-9])               KEY="num$k" ;;
        *)                   KEY="other" ;;
    esac
}

# menu_select VAR default_index "Label|hint" "Label|hint" ...   -> VAR = chosen index
menu_select() {
    local __var="$1" sel="$2"
    shift 2
    local -a labels=() hints=()
    local item n i cols first=1 d
    for item in "$@"; do
        labels+=("${item%%|*}")
        if [[ "$item" == *"|"* ]]; then
            hints+=("${item#*|}")
        else
            hints+=("")
        fi
    done
    n=${#labels[@]}
    cols=$(term_cols)
    echo
    printf '  %s↑/↓ choose · Enter select%s\n' "$DIM" "$NC"
    hide_cursor
    while true; do
        if [[ $first -eq 0 ]]; then
            printf '\e[%dA' $(( n + 1 ))
        fi
        first=0
        for (( i = 0; i < n; i++ )); do
            if [[ $i -eq $sel ]]; then
                printf '\r\e[K  %s❯ %d%s  %s%s%s\n' "$CYAN" $(( i + 1 )) "$NC" "$WHITE" "${labels[i]}" "$NC"
            else
                printf '\r\e[K    %s%d%s  %s\n' "$DIM" $(( i + 1 )) "$NC" "${labels[i]}"
            fi
        done
        printf '\r\e[K       %s%s%s\n' "$DIM" "$(trunc "${hints[sel]}" $(( cols - 9 )))" "$NC"
        read_key
        case "$KEY" in
            up)    sel=$(( (sel - 1 + n) % n )) ;;
            down)  sel=$(( (sel + 1) % n )) ;;
            enter) break ;;
            num*)
                d=${KEY#num}
                if (( d >= 1 && d <= n )); then sel=$(( d - 1 )); fi
                ;;
        esac
    done
    show_cursor
    printf -v "$__var" '%s' "$sel"
}

# Uses the global arrays CL_LABELS, CL_HINTS and CL_STATE (1 = on)
checklist_select() {
    local n i sel=0 first=1 cols box d
    n=${#CL_LABELS[@]}
    cols=$(term_cols)
    printf '  %s↑/↓ move · Space toggle · Enter continue%s\n\n' "$DIM" "$NC"
    hide_cursor
    while true; do
        if [[ $first -eq 0 ]]; then
            printf '\e[%dA' $(( n + 2 ))
        fi
        first=0
        for (( i = 0; i < n; i++ )); do
            if [[ ${CL_STATE[i]} -eq 1 ]]; then
                box="${GREEN}[✔]${NC}"
            else
                box="${DIM}[ ]${NC}"
            fi
            if [[ $i -eq $sel ]]; then
                printf '\r\e[K  %s❯%s %s %s%s%s\n' "$CYAN" "$NC" "$box" "$WHITE" "${CL_LABELS[i]}" "$NC"
            else
                printf '\r\e[K    %s %s\n' "$box" "${CL_LABELS[i]}"
            fi
        done
        printf '\r\e[K\n'
        printf '\r\e[K    %s%s%s\n' "$YELLOW" "$(trunc "${CL_HINTS[sel]}" $(( cols - 6 )))" "$NC"
        read_key
        case "$KEY" in
            up)    sel=$(( (sel - 1 + n) % n )) ;;
            down)  sel=$(( (sel + 1) % n )) ;;
            space) CL_STATE[sel]=$(( 1 - CL_STATE[sel] )) ;;
            enter) break ;;
            num*)
                d=${KEY#num}
                if (( d >= 1 && d <= n )); then
                    sel=$(( d - 1 ))
                    CL_STATE[sel]=$(( 1 - CL_STATE[sel] ))
                fi
                ;;
        esac
    done
    show_cursor
}

# ask_yn "Question" [danger] [default y|n]   -> exit status 0 = yes
ask_yn() {
    local q="$1" danger="${2:-}" def="${3:-n}" reply hint prompt
    if [[ "$def" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
    if [[ -n "$danger" ]]; then
        prompt="  ${P_RED}⚠ ${q}${P_NC} ${P_DIM}${hint}${P_NC} "
    else
        prompt="  ${P_CYAN}?${P_NC} ${P_WHITE}${q}${P_NC} ${P_DIM}${hint}${P_NC} "
    fi
    read -e -r -p "$prompt" reply
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ask_input VAR "Label" ["hint"] ["default"]
ask_input() {
    local __var="$1" label="$2" hint="${3:-}" def="${4:-}" val
    if [[ -n "$hint" ]]; then
        echo "    ${DIM}${hint}${NC}"
    fi
    read -e -r -i "$def" -p "  ${P_CYAN}➜${P_NC} ${P_WHITE}${label}:${P_NC} " val
    printf -v "$__var" '%s' "$val"
}

# ask_required VAR "Label" ["hint"] ["default"]  - repeats until non-empty
ask_required() {
    local __name="$1"
    while true; do
        ask_input "$@"
        if [[ -n "${!__name}" ]]; then
            return 0
        fi
        err "This field cannot be empty."
    done
}

# ask_secret VAR "Label"  - hidden input, repeats until non-empty
ask_secret() {
    local __var="$1" label="$2" val=""
    while true; do
        printf '  %s➜%s %s%s:%s %s(hidden)%s ' "$CYAN" "$NC" "$WHITE" "$label" "$NC" "$DIM" "$NC"
        read -r -s val
        echo
        if [[ -n "$val" ]]; then
            break
        fi
        err "This field cannot be empty."
    done
    printf -v "$__var" '%s' "$val"
}

press_enter() {
    local _x
    read -r -s -p "  ${DIM}Press Enter to continue...${NC}" _x || true
    echo
}

confirm_erase() {
    local ans
    echo
    echo "  ${RED}⚠  Formatting permanently deletes EVERYTHING on this ${LUN_SIZE_H} LUN.${NC}"
    if [[ $PROBE_PBS -eq 1 ]]; then
        echo "  ${RED}   That includes the PBS datastore with ${PROBE_GROUPS} backup group(s).${NC}"
    fi
    read -e -r -p "  ${P_WHITE}Type ${P_RED}ERASE${P_WHITE} to confirm, or press Enter to go back:${P_NC} " ans
    [[ "$ans" == "ERASE" ]]
}

# ---------------------------------------------------------------------------
# Quiet command runner: hides output, shows a spinner, logs to $LOG_FILE
# (the command line itself is NOT logged, so secrets never end up in the log)
# ---------------------------------------------------------------------------
_run_with_spinner() {
    local desc="$1"
    shift
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 start el
    local sz last_sz=-1 last_change last_line="" stall cols room extra="" colour
    { echo; echo "=== $(date '+%F %T')  $desc"; } >> "$LOG_FILE"
    hide_cursor
    mono; start=$MONO; last_change=$MONO
    "$@" </dev/null >> "$LOG_FILE" 2>&1 &
    BG_PID=$!
    cols=$(term_cols)
    while kill -0 "$BG_PID" 2>/dev/null; do
        # About once a second: has the command printed anything new?
        if (( i % 8 == 0 )); then
            sz=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
            if [[ "$sz" != "$last_sz" ]]; then
                last_sz=$sz
                last_change=$MONO
                # Progress meters (mkfs) redraw one line with \r and backspaces: show the newest value
                # shellcheck disable=SC2020
                last_line=$(tail -c 400 "$LOG_FILE" 2>/dev/null | tr '\b\r' '\n\n' | tr -cd '[:print:]\n' \
                    | grep -v '^[[:space:]]*$' | tail -n 1 | sed 's/^[[:space:]]*//')
                if [[ "$last_line" =~ ^([0-9]+)/([0-9]+)$ && ${BASH_REMATCH[2]} -gt 0 ]]; then
                    last_line="progress ${last_line} ($(( BASH_REMATCH[1] * 100 / BASH_REMATCH[2] ))%)"
                fi
            fi
        fi
        mono
        el=$(( MONO - start ))
        stall=$(( MONO - last_change ))
        room=$(( cols - ${#desc} - 18 ))
        extra=""
        colour="$DIM"
        if (( stall >= 300 )); then
            colour="$YELLOW"
            extra=" ⚠ no output for $(( stall / 60 )) min - may be stuck (log: ${LOG_FILE})"
        elif [[ -n "$last_line" ]]; then
            extra=" · ${last_line}"
        fi
        if (( room > 8 )); then
            extra=$(trunc "$extra" "$room")
        else
            extra=""
        fi
        printf '\r  %s%s%s %s %s(%02d:%02d)%s%s%s%s\033[K' "$CYAN" "${frames[i % 10]}" "$NC" "$desc" \
            "$DIM" $(( el / 60 )) $(( el % 60 )) "$NC" "$colour" "$extra" "$NC"
        i=$(( i + 1 ))
        sleep 0.12
    done
    RUN_RC=0
    wait "$BG_PID" || RUN_RC=$?
    BG_PID=""
    echo "--- exit code $RUN_RC" >> "$LOG_FILE"
    printf '\r\033[K'
    show_cursor
    if [[ $RUN_RC -eq 0 ]]; then
        mono
        el=$(( MONO - start ))
        printf '  %s✔%s %s %s(%02d:%02d)%s\n' "$GREEN" "$NC" "$desc" "$DIM" $(( el / 60 )) $(( el % 60 )) "$NC"
    fi
}

# Fatal on failure
run_quiet() {
    _run_with_spinner "$@"
    if [[ $RUN_RC -ne 0 ]]; then
        echo "  ${RED}✘ $1 failed (exit code ${RUN_RC})${NC}" >&2
        echo "  ${DIM}Last lines of ${LOG_FILE}:${NC}" >&2
        tail -n 15 "$LOG_FILE" | sed 's/^/    /' >&2
        exit 1
    fi
}

# Non-fatal: caller checks $RUN_RC
run_quiet_soft() {
    _run_with_spinner "$@"
}

# Is any APT source still pointing at the (subscription-only) enterprise repo?
enterprise_repo_active() {
    local f
    shopt -s nullglob
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        grep -qE '^[[:space:]]*deb .*enterprise\.proxmox\.com' "$f" 2>/dev/null && { shopt -u nullglob; return 0; }
    done
    for f in /etc/apt/sources.list.d/*.sources; do
        if grep -qi 'enterprise\.proxmox\.com' "$f" 2>/dev/null \
            && ! grep -qiE '^Enabled:[[:space:]]*(no|false)' "$f"; then
            shopt -u nullglob; return 0
        fi
    done
    shopt -u nullglob
    return 1
}

# Switch the enterprise repo off (it answers 401 without a paid subscription).
disable_enterprise_repos() {
    local f changed=0
    shopt -s nullglob
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        if grep -qE '^[[:space:]]*deb .*enterprise\.proxmox\.com' "$f" 2>/dev/null; then
            sed -i '/enterprise\.proxmox\.com/s/^[[:space:]]*deb /# deb /' "$f"
            ok "Disabled the enterprise repository in $(basename "$f")"; changed=1
        fi
    done
    for f in /etc/apt/sources.list.d/*.sources; do
        if grep -qi 'enterprise\.proxmox\.com' "$f" 2>/dev/null \
            && ! grep -qiE '^Enabled:[[:space:]]*(no|false)' "$f"; then
            if grep -qi '^Enabled:' "$f"; then
                sed -i 's/^Enabled:.*/Enabled: false/I' "$f"
            else
                echo "Enabled: false" >> "$f"
            fi
            ok "Disabled the enterprise repository in $(basename "$f")"; changed=1
        fi
    done
    shopt -u nullglob
    # Last resort: still active? move the file out of the way.
    if enterprise_repo_active; then
        shopt -s nullglob
        for f in /etc/apt/sources.list.d/*enterprise*; do
            [[ "$f" == *.disabled ]] && continue
            mv "$f" "$f.disabled" && ok "Moved $(basename "$f") out of the way" && changed=1
        done
        shopt -u nullglob
    fi
    [[ $changed -eq 1 ]]
}

apt_update() {
    run_quiet_soft "Updating package lists" apt-get -q update
    if [[ $RUN_RC -ne 0 ]]; then
        if enterprise_repo_active; then
            APT_WARN="enterprise repo needs a subscription"
            warn "The Proxmox ENTERPRISE repository answers 401 without a paid subscription."
            if [[ ${DO_REPO:-0} -eq 1 ]]; then
                disable_enterprise_repos || true
                run_quiet_soft "Updating package lists (enterprise repo off)" apt-get -q update
                [[ $RUN_RC -eq 0 ]] && APT_WARN=""
            else
                warn "Re-run the installer and tick the no-subscription repository option."
            fi
        else
            APT_WARN="apt update had warnings"
            warn "apt update reported warnings (see $LOG_FILE) - continuing"
        fi
    fi
    APT_UPDATED=1
}

# ---------------------------------------------------------------------------
# iSCSI helpers
# ---------------------------------------------------------------------------
detect_iscsi_service() {
    if systemctl list-unit-files iscsid.service 2>/dev/null | grep -q '^iscsid.service'; then
        ISCSI_SERVICE="iscsid.service"
    elif systemctl list-unit-files open-iscsi.service 2>/dev/null | grep -q '^open-iscsi.service'; then
        ISCSI_SERVICE="open-iscsi.service"
    else
        fatal "Neither iscsid nor open-iscsi service found - is open-iscsi installed?"
    fi
}

ensure_iscsi_service() {
    detect_iscsi_service
    if ! systemctl is-active "$ISCSI_SERVICE" >/dev/null 2>&1; then
        systemctl start "$ISCSI_SERVICE" >/dev/null 2>&1 || true
        sleep 2
        if ! systemctl is-active "$ISCSI_SERVICE" >/dev/null 2>&1; then
            systemctl status "$ISCSI_SERVICE" --no-pager --lines=5 >&2 || true
            fatal "Failed to start $ISCSI_SERVICE"
        fi
    fi
}

# Exact match on the IQN (so ...Target-1 never matches ...Target-10)
session_active() {
    iscsiadm -m session 2>/dev/null | awk -v t="$TARGET_IQN" '$4 == t { f = 1 } END { exit !f }'
}

node_update() {
    iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" -o update -n "$1" -v "$2" >/dev/null
}

# Creates a node record for ONLY the chosen target (discovery itself stores nothing)
create_node_record() {
    NODE_PREEXISTED=1
    if ! iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" >/dev/null 2>&1; then
        iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" -o new >/dev/null
        NODES_CREATED+=("${TARGET_IQN}|${PORTAL_IP}")
        NODE_PREEXISTED=0
    fi
}

# Value of one setting in a node record:  node_field PORTAL IQN node.startup
node_field() {
    iscsiadm -m node -T "$2" -p "$1" -o show 2>/dev/null \
        | awk -F' = ' -v k="$3" '$1 == k { print $2; exit }' || true
}

# chap | none | incomplete | missing        node_auth_state PORTAL IQN
# (iscsiadm masks the stored password, so "chap" means: method CHAP, and both the
#  username and the password are set - an empty password shows up as <empty>)
node_auth_state() {
    local am user pw
    if ! iscsiadm -m node -T "$2" -p "$1" >/dev/null 2>&1; then
        echo missing
        return 0
    fi
    am=$(node_field "$1" "$2" node.session.auth.authmethod)
    user=$(node_field "$1" "$2" node.session.auth.username)
    pw=$(node_field "$1" "$2" node.session.auth.password)
    if [[ "$am" == "CHAP" ]]; then
        if [[ -n "$user" && "$user" != "<empty>" && -n "$pw" && "$pw" != "<empty>" ]]; then
            echo chap
        else
            echo incomplete
        fi
    else
        echo none
    fi
}

stored_chap_state() {
    node_auth_state "$PORTAL_IP" "$TARGET_IQN"
}

# "iqn|portal" of every drive that was set up by this script (read from its monitor script)
installed_nodes() {
    local f TARGET PORTAL
    for f in /usr/local/bin/check-iscsi-session-*.sh; do
        if [[ ! -f "$f" ]]; then continue; fi
        TARGET=""; PORTAL=""
        # shellcheck disable=SC1090
        source <(grep -E '^(TARGET|PORTAL)=' "$f")
        if [[ -n "$TARGET" ]]; then
            echo "${TARGET}|$(norm_portal "$PORTAL")"
        fi
    done
}

# "address:port" without the ",tpgt" that iscsiadm appends
norm_portal() {
    local p="${1%%,*}"
    if [[ ! "$p" =~ :[0-9]+$ ]]; then
        p="${p}:3260"
    fi
    echo "$p"
}

# Prints "portal|iqn" for every node record stored on this server
list_node_records() {
    iscsiadm -m node 2>/dev/null | awk 'NF >= 2 { split($1, a, ","); print a[1] "|" $2 }' || true
}

# Records that no installation uses (not in KNOWN_NODES) and that have no running
# session. Prints "portal|iqn|startup|auth-state".
find_stale_records() {
    local rec portal iqn k is_known
    while IFS= read -r rec; do
        if [[ -z "$rec" ]]; then continue; fi
        portal="${rec%%|*}"
        iqn="${rec#*|}"
        is_known=0
        for k in "${KNOWN_NODES[@]}"; do
            if [[ "$k" == "${iqn}|$(norm_portal "$portal")" ]]; then
                is_known=1
            fi
        done
        if [[ $is_known -eq 1 ]]; then continue; fi
        if iscsiadm -m session 2>/dev/null | awk -v t="$iqn" '$4 == t { f = 1 } END { exit !f }'; then
            continue
        fi
        echo "${portal}|${iqn}|$(node_field "$portal" "$iqn" node.startup)|$(node_auth_state "$portal" "$iqn")"
    done < <(list_node_records)
}

# During setup: shows leftover records (old tests, other portals, older script
# versions) and offers to remove them. They log in at boot and fill the
# Synology's log with failed logins when they have no valid CHAP login.
offer_stale_cleanup() {
    local -a stale=()
    local rec portal iqn startup auth broken=0 choice def=1 line
    KNOWN_NODES=("${TARGET_IQN}|$(norm_portal "$PORTAL_IP")")
    mapfile -t -O 1 KNOWN_NODES < <(installed_nodes)    # drives set up earlier are never "stale"
    mapfile -t stale < <(find_stale_records)
    if [[ ${#stale[@]} -eq 0 ]]; then
        return 0
    fi
    echo
    panel_top "Other iSCSI records on this server" "$YELLOW"
    panel_line "Not used by this installation, and no running session:"
    panel_blank
    for rec in "${stale[@]}"; do
        IFS='|' read -r portal iqn startup auth <<< "$rec"
        line="${iqn##*:}  ${portal}  ${DIM}boot login: ${startup:-?} · CHAP: ${auth}${NC}"
        if [[ "$startup" == "automatic" && "$auth" != "chap" ]]; then
            broken=$(( broken + 1 ))
            panel_line "${RED}✘${NC} ${line}"
        else
            panel_line "• ${line}"
        fi
    done
    if [[ $broken -gt 0 ]]; then
        panel_blank
        panel_line "${RED}✘ = tries to log in at boot without a valid CHAP login. The Synology${NC}"
        panel_line "${RED}  logs every attempt as a failed login.${NC}"
    fi
    panel_bottom
    if [[ $broken -eq ${#stale[@]} ]]; then
        def=0
    fi
    menu_select choice "$def" \
        "Remove these ${#stale[@]} record(s)|Deletes only the saved iSCSI settings on this server - nothing on the Synology" \
        "Keep them|Leave everything as it is"
    if [[ $choice -eq 0 ]]; then
        for rec in "${stale[@]}"; do
            IFS='|' read -r portal iqn startup auth <<< "$rec"
            if iscsiadm -m node -T "$iqn" -p "$portal" -o delete >/dev/null 2>&1; then
                ok "Removed ${iqn##*:} at ${portal}"
            else
                warn "Could not remove ${iqn##*:} at ${portal}"
            fi
        done
    fi
}

# Writes the authentication settings into the node record (never on screen or in the log)
apply_auth() {
    if [[ $CHAP_KEEP -eq 1 ]]; then
        return 0    # keep the CHAP login that is already stored in the record
    fi
    if [[ $CHAP_MODE -eq 1 ]]; then
        if [[ -z "$CHAP_USER" || -z "$CHAP_PASS" ]]; then
            fatal "Safety stop: no CHAP username/password is available - refusing to overwrite the stored login with empty values."
        fi
        node_update node.session.auth.authmethod CHAP
        node_update node.session.auth.username "$CHAP_USER"
        node_update node.session.auth.password "$CHAP_PASS"
    else
        node_update node.session.auth.authmethod None
    fi
}

# Removes node records created during setup that are not the chosen target
prune_other_nodes() {
    local n
    for n in "${NODES_CREATED[@]}"; do
        if [[ $DO_ISCSI -eq 0 || "${n%%|*}" != "$TARGET_IQN" ]]; then
            iscsiadm -m node -T "${n%%|*}" -p "${n#*|}" -o delete >/dev/null 2>&1 || true
        fi
    done
    NODES_CREATED=()
}

logout_probe() {
    if [[ $PROBE_SESSION -eq 1 ]]; then
        iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" --logout >/dev/null 2>&1 || true
        udevadm settle >/dev/null 2>&1 || true
        PROBE_SESSION=0
    fi
}

# Prints every /dev/sdX that is attached (and running) for $TARGET_IQN, one per line
get_target_devices() {
    iscsiadm -m session -P 3 2>/dev/null | awk -v t="$TARGET_IQN" '
        /^[[:space:]]*Target:/ { in_t = ($2 == t) }
        in_t && /Attached scsi disk/ && /State: running/ { print "/dev/" $4 }
    ' || true
}

# Waits (max ~20s, with one rescan) for the target's disk(s) to show up.
# Prints all of them, one per line (a target can hold several LUNs).
wait_for_devices() {
    local devs d attempt rescanned=0 all_ready
    for attempt in $(seq 1 20); do
        devs=$(get_target_devices)
        if [[ -n "$devs" ]]; then
            # give further LUNs of the same target a moment to appear
            sleep 2
            udevadm settle >/dev/null 2>&1 || true
            devs=$(get_target_devices)
            all_ready=1
            while IFS= read -r d; do
                if [[ -n "$d" && ! -b "$d" ]]; then
                    all_ready=0
                fi
            done <<< "$devs"
            if [[ $all_ready -eq 1 && -n "$devs" ]]; then
                echo "$devs"
                return 0
            fi
        fi
        if [[ $attempt -eq 10 && $rescanned -eq 0 ]]; then
            iscsiadm -m session --rescan >/dev/null 2>&1 || true
            rescanned=1
        fi
        sleep 1
    done
    return 1
}

# lun_attr /dev/sdX COLUMN  ->  one lsblk value (WWN, SERIAL, SIZE, HCTL ...), trimmed
lun_attr() {
    lsblk -dno "$2" "$1" 2>/dev/null | head -n 1 | xargs || true
}

# SCSI LUN number of a disk (last field of the H:C:T:L address)
lun_number() {
    local h
    h=$(lun_attr "$1" HCTL)
    echo "${h##*:}"
}

# One-line description of what is on a disk (used by the LUN picker)
lun_summary() {
    local dev="$1" mnt types parts
    mnt=$(lsblk -nro MOUNTPOINT "$dev" 2>/dev/null | grep -m1 '[^[:space:]]' || true)
    if [[ -n "$mnt" ]]; then
        echo "mounted at ${mnt}"
        return 0
    fi
    types=$(lsblk -nro FSTYPE "$dev" 2>/dev/null | awk 'NF' | sort -u | paste -sd, - || true)
    parts=$(lsblk -nlo TYPE "$dev" 2>/dev/null | grep -c '^part$' || true)
    if [[ -n "$types" ]]; then
        echo "contains: ${types}"
    elif [[ "${parts:-0}" -gt 0 ]]; then
        echo "partitioned, no filesystem"
    else
        echo "empty - no partition table"
    fi
}

# From a list of devices (one per line), prints the one that is the LUN chosen
# during setup. Matches on WWN, then serial, then SCSI LUN number.
pick_chosen_lun() {
    local devs="$1" d count
    count=$(grep -c . <<< "$devs" || true)
    if [[ -z "$LUN_WWN" && -z "$LUN_SERIAL" && -z "$LUN_NUM" ]]; then
        if [[ "$count" -eq 1 ]]; then
            echo "$devs"
            return 0
        fi
        return 1
    fi
    while IFS= read -r d; do
        if [[ -z "$d" ]]; then continue; fi
        if [[ -n "$LUN_WWN" ]]; then
            if [[ "$(lun_attr "$d" WWN)" == "$LUN_WWN" ]]; then echo "$d"; return 0; fi
        elif [[ -n "$LUN_SERIAL" ]]; then
            if [[ "$(lun_attr "$d" SERIAL)" == "$LUN_SERIAL" ]]; then echo "$d"; return 0; fi
        else
            if [[ "$(lun_number "$d")" == "$LUN_NUM" ]]; then echo "$d"; return 0; fi
        fi
    done <<< "$devs"
    return 1
}

# Lets the user choose between several LUNs on the target -> sets DEVICE_PATH
choose_lun() {
    local -a items=()
    local d sz model num choice
    for d in "${LUN_DEVS[@]}"; do
        sz=$(lun_attr "$d" SIZE)
        model=$(lsblk -dno VENDOR,MODEL "$d" 2>/dev/null | head -n 1 | xargs || true)
        num=$(lun_number "$d")
        items+=("${d}  ${sz}  ${model}  (LUN ${num:-?})|WWN $(lun_attr "$d" WWN)  ·  $(lun_summary "$d")")
    done
    echo
    panel_top "This target holds ${#LUN_DEVS[@]} LUNs" "$YELLOW"
    panel_line "Pick the one that should store the backups."
    panel_line "${DIM}The other LUNs are not touched.${NC}"
    panel_bottom
    menu_select choice 0 "${items[@]}" "Quit|Nothing has been changed"
    if [[ $choice -ge ${#LUN_DEVS[@]} ]]; then
        quit_clean
    fi
    DEVICE_PATH="${LUN_DEVS[choice]}"
    ok "LUN: ${DEVICE_PATH}"
}

# Raises the reconnect patience of the LIVE session (the node record only
# applies at the next login). Returns 1 if there is no session to change.
apply_live_timeout() {
    local sid f
    sid=$(iscsiadm -m session 2>/dev/null | awk -v t="$TARGET_IQN" '$4 == t { gsub(/\[|\]/, "", $2); print $2; exit }')
    f="/sys/class/iscsi_session/session${sid}/recovery_tmo"
    if [[ -n "$sid" && -w "$f" ]]; then
        echo "$REPLACEMENT_TIMEOUT" > "$f" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

# Removes device-mapper volumes (e.g. auto-activated LVM) that sit on top of the LUN
release_holders() {
    local base blk h dm_name
    base=$(basename "$DEVICE_PATH")
    for blk in "/sys/block/${base}" "/sys/block/${base}/${base}"*; do
        if [[ ! -d "$blk/holders" ]]; then continue; fi
        for h in "$blk"/holders/*; do
            if [[ ! -e "$h" ]]; then continue; fi
            dm_name=$(cat "/sys/block/$(basename "$h")/dm/name" 2>/dev/null || true)
            if [[ -n "$dm_name" ]]; then
                dmsetup remove "$dm_name" >> "$LOG_FILE" 2>&1 || true
                ok "Released device-mapper volume ${dm_name}"
            fi
        done
    done
}

# ---------------------------------------------------------------------------
# LUN inspection (read-only)
# ---------------------------------------------------------------------------
# Thin or thick? The disk reports it itself (SCSI "Logical Block Provisioning" page and the
# kernel's discard mode). Prints one of:
#   thin      thin LUN, space reclamation (UNMAP) works
#   thin-off  thin LUN, but space reclamation is switched off on the NAS
#   thick     thick LUN: space is reserved, nothing can be given back
#   unknown   the disk does not say
lun_provisioning() {
    local d="$1" mode b6 type=0
    mode=$(cat /sys/block/"${d}"/device/scsi_disk/*/provisioning_mode 2>/dev/null | head -n 1 || true)
    read -r _ b6 < <(od -An -tu1 -j5 -N2 "/sys/block/${d}/device/vpd_pgb2" 2>/dev/null) || true
    if [[ "${b6:-}" =~ ^[0-9]+$ ]]; then
        type=$(( b6 & 7 ))        # 1 = resource provisioned (thick), 2 = thin provisioned
    fi
    if (( type == 1 )); then
        echo thick
    elif [[ "$mode" == "unmap" ]]; then
        echo thin
    elif (( type == 2 )); then
        echo thin-off
    elif [[ -n "$mode" ]]; then
        echo thick
    else
        echo unknown
    fi
}

probe_lun() {
    local dev="$DEVICE_PATH" base disc devfs pttype t p opts dir chunks ds_root
    local -a parts=() candidates=()
    base=$(basename "$dev")

    PROBE_NODE=""; PROBE_FS=""; PROBE_UUID=""; PROBE_OTHER=""
    PROBE_MOUNTED_AT=""; PROBE_INSPECTED=0; PROBE_PBS=0; PROBE_PBS_SUB=""
    PROBE_GROUPS=0; PROBE_LATEST=""; PROBE_USED=""; PROBE_FILES=0

    LUN_SIZE=$(lsblk -dnbo SIZE "$dev" 2>/dev/null | tr -d ' ' || true)
    LUN_SIZE_H=$(lsblk -dno SIZE "$dev" 2>/dev/null | tr -d ' ' || true)
    LUN_WWN=$(lsblk -dno WWN "$dev" 2>/dev/null | tr -d ' ' || true)
    LUN_SERIAL=$(lun_attr "$dev" SERIAL)
    LUN_NUM=$(lun_number "$dev")
    LUN_MODEL=$(lsblk -dno VENDOR,MODEL "$dev" 2>/dev/null | xargs || true)
    LUN_PROV=$(lun_provisioning "$base")
    LUN_DISCARD=0
    case "$LUN_PROV" in
        thin) LUN_DISCARD=1 ;;
        unknown)
            disc=$(cat "/sys/block/${base}/queue/discard_max_bytes" 2>/dev/null || echo 0)
            if [[ "$disc" =~ ^[0-9]+$ ]] && (( disc > 0 )); then
                LUN_DISCARD=1
            fi
            ;;
    esac

    pttype=$(blkid -p -s PTTYPE -o value "$dev" 2>/dev/null || true)
    devfs=$(blkid -p -s TYPE -o value "$dev" 2>/dev/null || true)
    mapfile -t parts < <(lsblk -nlo NAME,TYPE "$dev" 2>/dev/null | awk '$2 == "part" { print "/dev/" $1 }')
    LUN_LAYOUT=$(lsblk -no NAME,SIZE,FSTYPE,LABEL "$dev" 2>/dev/null || true)

    LUN_EMPTY=0
    if [[ -z "$pttype" && -z "$devfs" && ${#parts[@]} -eq 0 ]]; then
        LUN_EMPTY=1
        return 0
    fi

    if [[ -n "$devfs" ]]; then
        candidates=("$dev")
    else
        candidates=("${parts[@]}")
    fi
    for p in "${candidates[@]}"; do
        t=$(blkid -p -s TYPE -o value "$p" 2>/dev/null || true)
        case "$t" in
            ext2|ext3|ext4|xfs)
                if [[ -z "$PROBE_NODE" ]]; then
                    PROBE_NODE="$p"
                    PROBE_FS="$t"
                fi
                ;;
            "") ;;
            *) PROBE_OTHER+="$t " ;;
        esac
    done
    PROBE_OTHER="${PROBE_OTHER% }"

    if [[ -z "$PROBE_NODE" ]]; then
        return 0
    fi
    PROBE_UUID=$(blkid -p -s UUID -o value "$PROBE_NODE" 2>/dev/null || true)
    PROBE_MOUNTED_AT=$(findmnt -nro TARGET -S "$PROBE_NODE" 2>/dev/null | head -n 1 || true)

    dir=""
    if [[ -n "$PROBE_MOUNTED_AT" ]]; then
        dir="$PROBE_MOUNTED_AT"
    else
        PROBE_TMP=$(mktemp -d /tmp/pbs-lun-probe.XXXXXX)
        if [[ "$PROBE_FS" == "xfs" ]]; then opts="ro,norecovery"; else opts="ro,noload"; fi
        if mount -o "$opts" "$PROBE_NODE" "$PROBE_TMP" >> "$LOG_FILE" 2>&1; then
            dir="$PROBE_TMP"
        fi
    fi

    if [[ -n "$dir" ]]; then
        PROBE_INSPECTED=1
        chunks=$(find "$dir" -maxdepth 3 -type d -name .chunks -print -quit 2>/dev/null || true)
        if [[ -n "$chunks" ]]; then
            PROBE_PBS=1
            ds_root=$(dirname "$chunks")
            PROBE_PBS_SUB="${ds_root#"$dir"}"
            PROBE_GROUPS=$(find "$ds_root/vm" "$ds_root/ct" "$ds_root/host" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            PROBE_LATEST=$(find "$ds_root/vm" "$ds_root/ct" "$ds_root/host" -mindepth 2 -maxdepth 2 -type d -name '20*' -printf '%f\n' 2>/dev/null | sort | tail -n 1)
        fi
        PROBE_USED=$(df -h --output=used "$dir" 2>/dev/null | tail -n 1 | tr -d ' ')
        PROBE_FILES=$(find "$dir" -mindepth 1 -maxdepth 1 ! -name lost+found 2>/dev/null | head -n 50 | wc -l)
    fi

    if [[ -n "$PROBE_TMP" ]]; then
        umount "$PROBE_TMP" >> "$LOG_FILE" 2>&1 || true
        rmdir "$PROBE_TMP" 2>/dev/null || true
        PROBE_TMP=""
    fi
}

show_lun_report() {
    local line
    panel_top "LUN on ${TARGET_IQN##*:}"
    kv "Device" "${DEVICE_PATH}  ${DIM}${LUN_MODEL}${NC}"
    kv "Size" "${WHITE}${LUN_SIZE_H}${NC}"
    case "$LUN_PROV" in
        thin)
            kv "LUN type" "${GREEN}thin${NC} ${DIM}· space reclamation is on - weekly TRIM gives space back${NC}" ;;
        thin-off)
            kv "LUN type" "${YELLOW}thin, space reclamation is OFF${NC}"
            kv "" "${DIM}Deleted backups will not free space. DSM › SAN Manager › LUN › Edit${NC}" ;;
        thick)
            kv "LUN type" "${CYAN}thick${NC} ${DIM}· space is reserved on the NAS, TRIM is not needed${NC}" ;;
        *)
            if [[ $LUN_DISCARD -eq 1 ]]; then
                kv "LUN type" "${DIM}not reported · accepts TRIM${NC}"
            else
                kv "LUN type" "${DIM}not reported · no TRIM${NC}"
            fi ;;
    esac

    if [[ $LUN_EMPTY -eq 1 ]]; then
        kv "Contents" "${GREEN}empty - ready to be prepared${NC}"
        panel_bottom
        return 0
    fi

    panel_blank
    while IFS= read -r line; do
        panel_line "  ${DIM}${line}${NC}"
    done <<< "$LUN_LAYOUT"
    panel_blank

    if [[ -n "$PROBE_MOUNTED_AT" ]]; then
        kv "Status" "${CYAN}already mounted on this server at ${PROBE_MOUNTED_AT}${NC}"
    fi
    if [[ $PROBE_PBS -eq 1 ]]; then
        kv "Contents" "${YELLOW}existing PBS datastore${NC} ${DIM}(${PROBE_PBS_SUB:-/} on the LUN)${NC}"
        kv "Backup groups" "${PROBE_GROUPS}"
        if [[ -n "$PROBE_LATEST" ]]; then
            kv "Latest backup" "${PROBE_LATEST}"
        fi
        kv "Used space" "${PROBE_USED}"
    elif [[ -n "$PROBE_NODE" && $PROBE_INSPECTED -eq 1 ]]; then
        if [[ $PROBE_FILES -gt 0 ]]; then
            kv "Contents" "${YELLOW}${PROBE_FS} filesystem with data${NC} ${DIM}(${PROBE_USED} used)${NC}"
        else
            kv "Contents" "${GREEN}empty ${PROBE_FS} filesystem${NC}"
        fi
    elif [[ -n "$PROBE_NODE" ]]; then
        kv "Contents" "${YELLOW}${PROBE_FS} filesystem (could not be opened read-only)${NC}"
    fi
    if [[ "$PROBE_OTHER" == *LVM2_member* ]]; then
        kv "Warning" "${RED}LVM found - this LUN may belong to a Proxmox VE or other server!${NC}"
    elif [[ -n "$PROBE_OTHER" ]]; then
        kv "Other" "${YELLOW}unsupported content: ${PROBE_OTHER}${NC}"
    elif [[ -z "$PROBE_NODE" ]]; then
        kv "Contents" "${YELLOW}partition table without a usable filesystem${NC}"
    fi
    panel_bottom
}

# ---------------------------------------------------------------------------
# Datastore helpers
# ---------------------------------------------------------------------------
reuse_supported() {
    if [[ -z "$REUSE_OK" ]]; then
        REUSE_OK=0
        if { proxmox-backup-manager help datastore create --verbose 2>&1 || true
             proxmox-backup-manager datastore create 2>&1 || true; } | grep -q 'reuse-datastore'; then
            REUSE_OK=1
        fi
    fi
    [[ $REUSE_OK -eq 1 ]]
}

ds_exists() {
    proxmox-backup-manager datastore show "$1" >/dev/null 2>&1
}

valid_ds_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{2,31}$ ]]
}

# ===========================================================================
# SETUP (interactive - nothing on any disk is changed here)
# ===========================================================================
preflight() {
    if [[ $EUID -ne 0 ]]; then
        echo "${RED}This script must be run as root${NC}" >&2
        exit 1
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "This installer is interactive - run it directly in a terminal (not piped)." >&2
        echo "Download the file first, read it, then run it from a terminal: ./pbs-post-install.sh" >&2
        exit 1
    fi
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    echo "=== PBS post-install v${VERSION} started $(date '+%F %T')" >> "$LOG_FILE"

    # shellcheck disable=SC1091
    OS_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    # shellcheck disable=SC1091
    OS_PRETTY=$(. /etc/os-release && echo "${PRETTY_NAME:-Debian}")
    if [[ -z "$OS_CODENAME" ]]; then
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || true)
    fi
    if [[ -z "$OS_CODENAME" ]]; then
        fatal "Could not detect the Debian codename (e.g. bookworm / trixie). Aborting."
    fi
    PBS_VERSION=$(proxmox-backup-manager versions 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    HOST_NAME=$(hostname -f 2>/dev/null || hostname)
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    INITIATOR_IQN=$(awk -F= '/^InitiatorName=/ {print $2}' /etc/iscsi/initiatorname.iscsi 2>/dev/null || true)
}

setup_welcome() {
    local choice cols rows
    CURRENT_TASK="Welcome"
    cols=$(term_cols)
    rows=$(term_rows)
    printf '\033[2J\033[H'
    render_banner
    echo
    panel_top "This server"
    kv "Hostname" "$HOST_NAME"
    kv "IP address" "${HOST_IP:-unknown}"
    kv "PBS version" "${PBS_VERSION:-${YELLOW}not detected${NC}}"
    kv "OS" "$OS_PRETTY"
    panel_bottom
    echo
    panel_top "What this installer does"
    panel_line "${GREEN}●${NC} Switches to the free no-subscription repository and upgrades"
    panel_line "${GREEN}●${NC} Guides you through creating the LUN on your Synology"
    panel_line "${GREEN}●${NC} Connects and inspects the LUN - formats only if you allow it"
    panel_line "${GREEN}●${NC} Mounts it safely, monitors the connection, enables TRIM"
    panel_line "${GREEN}●${NC} Creates - or re-attaches - the PBS datastore"
    panel_line "${GREEN}●${NC} Removes the \"No valid subscription\" popup"
    panel_line "${GREEN}●${NC} Adds a live dashboard + menu that greets you at login"
    panel_bottom
    echo
    echo "  ${WHITE}All questions come first.${NC} ${DIM}No disk is changed until you confirm the plan.${NC}"
    if [[ -z "$PBS_VERSION" ]]; then
        warn "proxmox-backup-manager was not found - this does not look like a Proxmox Backup Server."
    fi
    if (( cols < 80 || rows < 30 )); then
        warn "Your terminal is ${cols}x${rows} - 80x30 or larger looks best."
    fi
    menu_select choice 0 \
        "Start the setup|About 2 minutes of questions - then the installer runs on its own" \
        "Quit|Nothing has been changed"
    if [[ $choice -ne 0 ]]; then
        quit_clean
    fi
}

setup_options() {
    while true; do
        render_setup 1
        echo "  Choose what the installer should do. ${DIM}(all on = recommended for a fresh server)${NC}"
        echo
        CL_LABELS=(
            "Switch to the no-subscription repository"
            "Upgrade all packages (apt full-upgrade)"
            "Connect a Synology iSCSI LUN"
            "Create a PBS datastore"
            "Remove the subscription popup"
            "Login screen (MOTD dashboard + menu)"
        )
        CL_HINTS=(
            "Disables the enterprise repo (needs a paid subscription) and enables the free repo"
            "Recommended on a fresh install - can take a few minutes"
            "Installs open-iscsi, connects, inspects and mounts the LUN"
            "Registers the storage in PBS so backups can be stored there"
            "Hides the \"No valid subscription\" message at login - kept after updates"
            "Live status when you log in: server, Synology link, free space, backups - plus a menu"
        )
        CL_STATE=("$DO_REPO" "$DO_UPGRADE" "$DO_ISCSI" "$DO_DS" "$DO_NAG" "$DO_MOTD")
        checklist_select
        DO_REPO=${CL_STATE[0]}
        DO_UPGRADE=${CL_STATE[1]}
        DO_ISCSI=${CL_STATE[2]}
        DO_DS=${CL_STATE[3]}
        DO_NAG=${CL_STATE[4]}
        DO_MOTD=${CL_STATE[5]}
        if [[ $(( DO_REPO + DO_UPGRADE + DO_ISCSI + DO_DS + DO_NAG + DO_MOTD )) -gt 0 ]]; then
            return 0
        fi
        err "Nothing selected - pick at least one option."
        sleep 2
    done
}

setup_tools() {
    render_setup 2
    if command -v iscsiadm >/dev/null 2>&1 && command -v parted >/dev/null 2>&1 \
        && command -v mkfs.xfs >/dev/null 2>&1; then
        ok "iSCSI tools are already installed"
    else
        panel_top "Why this happens now"
        panel_line "To talk to the Synology - and safely look at the LUN before"
        panel_line "anything is changed - the iSCSI tools are installed first."
        panel_line "${GREEN}This does not touch any disk.${NC}"
        panel_bottom
        echo
        if [[ ${DO_REPO:-0} -eq 1 ]]; then
            disable_enterprise_repos || true
        fi
        apt_update
        run_quiet "Installing open-iscsi, parted and xfsprogs" \
            "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" install open-iscsi parted xfsprogs
    fi
    run_quiet "Loading iSCSI kernel modules" bash -c 'modprobe iscsi_tcp && modprobe scsi_transport_iscsi'
    grep -qxF "iscsi_tcp" /etc/modules || echo "iscsi_tcp" >> /etc/modules
    grep -qxF "scsi_transport_iscsi" /etc/modules || echo "scsi_transport_iscsi" >> /etc/modules
    run_quiet "Starting the iSCSI service" systemctl enable --now iscsid open-iscsi
    ensure_iscsi_service
    INITIATOR_IQN=$(awk -F= '/^InitiatorName=/ {print $2}' /etc/iscsi/initiatorname.iscsi 2>/dev/null || true)
    echo
    ok "This server's initiator name: ${WHITE}${INITIATOR_IQN:-unknown}${NC}"
    echo
    press_enter
}

guide_page_lun() {
    panel_top "1 · Create the LUN   ${DIM}DSM › SAN Manager › LUN › Create${NC}"
    panel_line "${WHITE}Name${NC}        e.g. PBS-Backup"
    panel_line "${WHITE}Location${NC}    the volume that should hold the backups"
    panel_line "${WHITE}Capacity${NC}    PBS deduplicates, but plan room for many versions"
    panel_line "${WHITE}Allocation${NC}  Thin or Thick - see below"
    panel_bottom
    panel_top "THIN provisioning · flexible, saves space" "$GREEN"
    panel_line "${GREEN}+${NC} Only uses NAS space for data that is actually written"
    panel_line "${GREEN}+${NC} With ${WHITE}Space reclamation${NC} enabled, space from pruned backups"
    panel_line "  goes back to the NAS (this installer enables weekly TRIM)"
    panel_line "${RED}−${NC} A little slower · the NAS volume can fill up if over-committed"
    panel_bottom
    panel_top "THICK provisioning · fastest, predictable" "$MAGENTA"
    panel_line "${GREEN}+${NC} Best and most consistent backup / restore performance"
    panel_line "${GREEN}+${NC} Space is reserved - backups can never fail because the NAS is full"
    panel_line "${RED}−${NC} Uses the full size on the NAS right away · no space reclamation"
    panel_bottom
    echo "  ${YELLOW}Tip:${NC} not sure? Pick ${WHITE}Thin + Space reclamation${NC} if the volume is shared with"
    echo "       other data. Pick ${WHITE}Thick${NC} if the volume is dedicated to backups."
}

guide_page_target() {
    panel_top "2 · Create the iSCSI target   ${DIM}in the LUN wizard, or SAN Manager › iSCSI${NC}"
    panel_line "Choose ${WHITE}Create a new iSCSI target${NC} and map the LUN to it"
    panel_line "Enable ${WHITE}CHAP${NC} and set a username + password ${DIM}(Synology: 12-16 characters)${NC}"
    panel_line "${DIM}You don't need to copy the IQN - you'll pick it from a list.${NC}"
    panel_bottom
    panel_top "3 · Allow only this PBS server"
    panel_line "Give this initiator access to the target / LUN (permissions / masking):"
    panel_line "  ${WHITE}${INITIATOR_IQN:-shown after the iSCSI tools are installed}${NC}"
    panel_line "Keep ${WHITE}Allow multiple sessions${NC} disabled on the target"
    panel_bottom
    panel_top "Important" "$RED"
    panel_line "Never connect the same LUN to two servers at the same time."
    panel_line "ext4 and XFS are not cluster filesystems - the data WILL be corrupted."
    panel_bottom
    panel_top "Network tips"
    panel_line "Use a wired link - ideally a dedicated NIC or VLAN for iSCSI -"
    panel_line "and the same MTU on both sides (jumbo frames on both, or on neither)."
    panel_bottom
}

setup_synology_guide() {
    local choice page=1
    if [[ $GUIDE_DONE -eq 1 ]]; then
        return 0
    fi
    while true; do
        render_setup 3
        if [[ $page -eq 1 ]]; then
            guide_page_lun
            menu_select choice 0 \
                "Next: target, CHAP and permissions|Page 2 of 2" \
                "Skip - my LUN and target are already set up|Go straight to the connection details" \
                "Quit|Come back when the LUN is ready - nothing has been changed"
            case "$choice" in
                0) page=2 ;;
                1) GUIDE_DONE=1; return 0 ;;
                *) quit_clean ;;
            esac
        else
            guide_page_target
            menu_select choice 0 \
                "Done - the LUN and target are ready|Continue to the connection details" \
                "Back to page 1|Thin vs thick provisioning" \
                "Quit|Come back when the LUN is ready - nothing has been changed"
            case "$choice" in
                0) GUIDE_DONE=1; return 0 ;;
                1) page=1 ;;
                *) quit_clean ;;
            esac
        fi
    done
}

choose_portal() {
    local host port rc out choice
    while true; do
        echo
        ask_required PORTAL_IP "Synology IP address" "the NAS address on your iSCSI network, e.g. 192.168.2.100" "$PORTAL_IP"
        PORTAL_IP="${PORTAL_IP// /}"
        host="$PORTAL_IP"
        port=3260
        if [[ "$PORTAL_IP" =~ ^(.+):([0-9]+)$ ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
        fi
        if ! timeout 4 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
            err "Cannot reach ${host} on port ${port}"
            echo "    ${YELLOW}Check the IP, that iSCSI is enabled on the Synology, and your network / firewall.${NC}"
            menu_select choice 0 "Enter the IP again" "Quit"
            if [[ $choice -ne 0 ]]; then quit_clean; fi
            continue
        fi
        ok "The Synology answers on ${host}:${port}"

        rc=0
        out=$(timeout 30 iscsiadm -m discovery -t sendtargets -p "$PORTAL_IP" -o nonpersistent 2>&1) || rc=$?
        mapfile -t DISCOVERED_TARGETS < <(awk '$2 ~ /^iqn\./ { print $2 }' <<< "$out" | sort -u)
        if [[ $rc -ne 0 || ${#DISCOVERED_TARGETS[@]} -eq 0 ]]; then
            err "The Synology did not offer any iSCSI targets"
            echo "    ${DIM}$(head -n 2 <<< "$out" | tr '\n' ' ')${NC}"
            echo "    ${YELLOW}Create a target (see the guide) and check that it is enabled.${NC}"
            menu_select choice 0 "Try again|Press Enter to keep the same IP" "Quit"
            if [[ $choice -ne 0 ]]; then quit_clean; fi
            continue
        fi
        ok "Found ${#DISCOVERED_TARGETS[@]} target(s)"
        return 0
    done
}

choose_target() {
    local -a items=()
    local t label sel=0 i choice
    for (( i = 0; i < ${#DISCOVERED_TARGETS[@]}; i++ )); do
        t="${DISCOVERED_TARGETS[i]}"
        label="$t"
        if [[ "$t" == "$TARGET_IQN" ]]; then sel=$i; fi
        if iscsiadm -m session 2>/dev/null | awk -v t="$t" '$4 == t { f = 1 } END { exit !f }'; then
            label+=" ${GREEN}(connected)${NC}"
        fi
        items+=("${label}|Target: ${t##*:}")
    done
    items+=("Enter an IQN manually|If your target is not in the list")
    echo
    echo "  ${WHITE}Which target holds the backup LUN?${NC}"
    menu_select choice "$sel" "${items[@]}"
    if [[ $choice -eq ${#DISCOVERED_TARGETS[@]} ]]; then
        ask_required TARGET_IQN "Target IQN" "e.g. iqn.2000-01.com.synology:DS923.Target-1.2c0d1f17e14" "$TARGET_IQN"
    else
        TARGET_IQN="${DISCOVERED_TARGETS[choice]}"
    fi
    ok "Target: ${TARGET_IQN}"
}

# ask_chap [fresh]   - "fresh" = do not offer the stored login (it was just rejected)
ask_chap() {
    local fresh="${1:-}" choice mode="new" st user
    st=$(stored_chap_state)
    echo
    echo "  ${WHITE}Authentication${NC}"
    if [[ "$st" == "chap" && "$fresh" != "fresh" ]]; then
        user=$(node_field "$PORTAL_IP" "$TARGET_IQN" node.session.auth.username)
        menu_select choice 0 \
            "Use the CHAP login already stored here (user: ${user})|Recommended - nothing has to be typed" \
            "Enter a new CHAP login|Replaces the stored one" \
            "No authentication|Only if CHAP is disabled on the target"
        case "$choice" in
            0) mode="keep" ;;
            1) mode="new" ;;
            *) mode="none" ;;
        esac
    else
        menu_select choice $(( CHAP_MODE == 1 ? 0 : 1 )) \
            "CHAP - username + password (recommended)|As set on the Synology: Target › Edit › Authentication" \
            "No authentication|Only if CHAP is disabled on the target"
        if [[ $choice -ne 0 ]]; then mode="none"; fi
    fi
    case "$mode" in
        keep)
            CHAP_MODE=1
            CHAP_KEEP=1
            ok "Using the stored CHAP login"
            ;;
        none)
            CHAP_MODE=0
            CHAP_KEEP=0
            CHAP_USER=""
            CHAP_PASS=""
            ;;
        *)
            CHAP_MODE=1
            CHAP_KEEP=0
            ask_required CHAP_USER "CHAP username" "" "$CHAP_USER"
            ask_secret CHAP_PASS "CHAP password"
            if (( ${#CHAP_PASS} < 12 || ${#CHAP_PASS} > 16 )); then
                warn "Synology CHAP passwords are normally 12-16 characters - double-check it."
            fi
            ;;
    esac
}

test_login() {
    create_node_record
    apply_auth
    # A fresh record must not log in by itself before the install; an existing
    # one keeps whatever boot setting it already has.
    if [[ $NODE_PREEXISTED -eq 0 ]]; then
        node_update node.startup manual
    fi
    echo
    run_quiet_soft "Logging in to ${TARGET_IQN##*:}" \
        timeout 30 iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" --login
    LOGIN_RC=$RUN_RC
    if [[ $LOGIN_RC -eq 0 ]]; then
        PROBE_SESSION=1
        ok "IP address, target and credentials are correct"
        return 0
    fi
    if [[ $LOGIN_RC -eq 15 ]]; then
        PROBE_SESSION=0
        return 0
    fi
    return 1
}

show_login_error() {
    local tailout
    tailout=$(grep -v '^===\|^---' "$LOG_FILE" | tail -n 2 | tr '\n' ' ')
    echo
    if [[ $LOGIN_RC -eq 24 ]]; then
        panel_top "Login rejected by the Synology" "$RED"
        panel_line "Usually one of these:"
        panel_line "  • the CHAP username or password is wrong"
        panel_line "  • this server is not allowed to use the target (permissions / masking)"
        panel_line "    This server's initiator name: ${WHITE}${INITIATOR_IQN:-unknown}${NC}"
    elif [[ $LOGIN_RC -eq 124 || $LOGIN_RC -eq 8 ]]; then
        panel_top "The Synology did not answer in time" "$RED"
        panel_line "Check the network and that the target is enabled."
    else
        panel_top "Login failed (exit code ${LOGIN_RC})" "$RED"
        panel_line "${DIM}${tailout}${NC}"
        panel_line "Check the target's permissions and that a LUN is mapped to it."
        panel_line "This server's initiator name: ${WHITE}${INITIATOR_IQN:-unknown}${NC}"
    fi
    panel_bottom
}

setup_connection() {
    local choice
    render_setup 4
    echo "  ${DIM}Everything is tested right away - before anything on this server is changed.${NC}"
    choose_portal
    while true; do
        choose_target
        if session_active; then
            ok "This server is already connected to that target"
            PROBE_SESSION=0
            case "$(stored_chap_state)" in
                chap)
                    CHAP_MODE=1
                    CHAP_KEEP=1
                    ok "Keeping the CHAP login already stored for this target"
                    ;;
                none)
                    CHAP_MODE=0
                    CHAP_KEEP=0
                    CHAP_USER=""
                    CHAP_PASS=""
                    ;;
                *)
                    warn "No complete CHAP login is stored for this target - enter it now."
                    echo "    ${DIM}It is saved for the next reconnect; the running connection is not touched.${NC}"
                    ask_chap fresh
                    ;;
            esac
            offer_stale_cleanup
            return 0
        fi
        ask_chap
        while true; do
            if test_login; then
                offer_stale_cleanup
                return 0
            fi
            show_login_error
            menu_select choice 0 \
                "Re-enter the login details|Username, password or authentication type" \
                "Try again|After fixing something on the Synology" \
                "Choose another target|Back to the target list" \
                "Quit|No disks have been touched"
            case "$choice" in
                0) ask_chap fresh ;;
                1) : ;;
                2) break ;;
                *) quit_clean ;;
            esac
        done
    done
}

choose_filesystem() {
    local choice def=0 rec="ext4"
    if [[ "$LUN_SIZE" =~ ^[0-9]+$ ]] && (( LUN_SIZE >= FOUR_TIB )); then
        def=1
        rec="XFS"
    fi
    echo
    panel_top "Choose a filesystem for the backups"
    panel_line "${WHITE}ext4${NC}  the proven Linux default · easy to repair · can be grown"
    panel_line "${WHITE}XFS${NC}   built for big volumes and millions of files · very fast to"
    panel_line "      format and check · can be grown, but never shrunk"
    panel_blank
    panel_line "Both are fully supported for PBS datastores. PBS stores backups as"
    panel_line "many small 'chunk' files - XFS handles that best on large LUNs."
    panel_line "Recommended for this ${LUN_SIZE_H} LUN: ${GREEN}${rec}${NC}"
    panel_bottom
    menu_select choice "$def" \
        "ext4|Created with 0% reserved blocks, so the whole LUN is usable for backups" \
        "XFS|Best choice for LUNs of 4 TB and larger"
    if [[ $choice -eq 0 ]]; then FS_TYPE="ext4"; else FS_TYPE="xfs"; fi
    ok "Filesystem: ${FS_TYPE}"
}

setup_lun() {
    local choice keep_label devs
    while true; do
        render_setup 5
        info "Waiting for the LUN to appear..."
        devs=$(wait_for_devices) || devs=""
        if [[ -n "$devs" ]]; then
            mapfile -t LUN_DEVS <<< "$devs"
            break
        fi
        err "The login worked, but no disk appeared."
        echo "    ${YELLOW}Most likely no LUN is mapped to this target on the Synology.${NC}"
        menu_select choice 0 "Try again|After mapping a LUN to the target" "Quit"
        if [[ $choice -ne 0 ]]; then quit_clean; fi
        iscsiadm -m session --rescan >/dev/null 2>&1 || true
    done
    if [[ ${#LUN_DEVS[@]} -gt 1 ]]; then
        choose_lun
        render_setup 5
    else
        DEVICE_PATH="${LUN_DEVS[0]}"
    fi
    info "Inspecting the LUN ${DIM}(read-only - nothing is written)${NC}"
    probe_lun
    render_setup 5
    show_lun_report

    if [[ -n "$PROBE_MOUNTED_AT" ]]; then
        DISK_ACTION="mounted"
        FS_TYPE="$PROBE_FS"
        echo
        ok "This LUN is already set up on this server - it will be kept exactly as it is."
        sleep 2
    elif [[ $LUN_EMPTY -eq 1 ]]; then
        DISK_ACTION="new"
        choose_filesystem
    else
        while true; do
            echo
            if [[ -n "$PROBE_NODE" ]]; then
                if [[ $PROBE_PBS -eq 1 ]]; then
                    keep_label="Keep it and re-attach the existing PBS datastore (recommended)"
                    warn "This LUN already contains backups."
                else
                    keep_label="Keep the existing ${PROBE_FS} filesystem and its data"
                    warn "This LUN is not empty."
                fi
                menu_select choice 0 \
                    "${keep_label}|Nothing on the LUN is erased" \
                    "${RED}Format the LUN - erase everything${NC}|Creates a new partition + filesystem" \
                    "Quit|Nothing has been changed"
                case "$choice" in
                    0)
                        DISK_ACTION="keep"
                        FS_TYPE="$PROBE_FS"
                        ok "The existing data will be kept"
                        break
                        ;;
                    2) quit_clean ;;
                esac
            else
                warn "This LUN contains something this installer cannot use."
                menu_select choice 0 \
                    "${RED}Format the LUN - erase everything${NC}|Only if you are sure nothing else uses this LUN" \
                    "Quit|Nothing has been changed"
                if [[ $choice -ne 0 ]]; then quit_clean; fi
            fi
            if confirm_erase; then
                DISK_ACTION="format"
                choose_filesystem
                break
            fi
            info "Not formatted - choose again."
        done
    fi
    logout_probe
    sleep 1
}

ask_mount_path() {
    local src
    while true; do
        echo
        ask_required MOUNT_PATH "Mount path" "where the LUN is mounted on this server" "${MOUNT_PATH:-/mnt/synology}"
        if [[ "$MOUNT_PATH" != /* || "$MOUNT_PATH" =~ [[:space:]] ]]; then
            err "The mount path must be absolute (start with /) and contain no spaces."
            continue
        fi
        if [[ "$MOUNT_PATH" != "/" ]]; then
            MOUNT_PATH="${MOUNT_PATH%/}"
        fi
        case "$MOUNT_PATH" in
            /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/lib*|/proc|/proc/*|/root|/run|/run/*|/sbin|/sbin/*|/sys|/sys/*|/usr|/usr/*|/var|/tmp|/home)
                err "${MOUNT_PATH} is a system directory - choose something like /mnt/synology."
                continue
                ;;
        esac
        if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
            src=$(findmnt -nro SOURCE "$MOUNT_PATH" 2>/dev/null || true)
            err "${MOUNT_PATH} is already in use by ${src:-another device}."
            continue
        fi
        if [[ -d "$MOUNT_PATH" && -n "$(ls -A "$MOUNT_PATH" 2>/dev/null)" ]]; then
            err "${MOUNT_PATH} exists and is not empty - choose an empty or new directory."
            continue
        fi
        if [[ $ADD_DRIVE -eq 1 && -e "/usr/local/bin/check-iscsi-session-$(basename "$MOUNT_PATH").sh" ]]; then
            err "A drive called '$(basename "$MOUNT_PATH")' is already set up - choose a different last part of the path."
            continue
        fi
        if awk -v p="$MOUNT_PATH" '!/^[[:space:]]*#/ && $2 == p { f = 1 } END { exit !f }' /etc/fstab; then
            warn "/etc/fstab already has an entry for ${MOUNT_PATH} - it will be replaced (a backup is kept)."
        fi
        ok "Mount path: ${MOUNT_PATH}"
        return 0
    done
}

setup_datastore_questions() {
    local default_path="" choice
    DS_REUSE=0
    DS_SKIP=0
    echo
    panel_top "PBS datastore"
    if [[ $DO_ISCSI -eq 1 ]]; then
        if [[ $PROBE_PBS -eq 1 && ( "$DISK_ACTION" == "keep" || "$DISK_ACTION" == "mounted" ) ]]; then
            DS_REUSE=1
            DS_PATH="${MOUNT_PATH}${PROBE_PBS_SUB}"
            panel_line "The existing datastore will be ${GREEN}re-attached${NC} - all backups stay."
            panel_line "Path: ${WHITE}${DS_PATH}${NC}"
            if ! reuse_supported; then
                panel_line "${YELLOW}This PBS version cannot re-attach from the command line (needs 3.3+).${NC}"
                panel_line "${YELLOW}The LUN is still mounted - add it afterwards in the web UI.${NC}"
            fi
        elif [[ "$DISK_ACTION" == "keep" && $PROBE_FILES -gt 0 ]]; then
            default_path="${MOUNT_PATH}/pbs-datastore"
            panel_line "The LUN contains other files, so a sub-folder is suggested."
        else
            default_path="$MOUNT_PATH"
            panel_line "The datastore will use the whole LUN."
        fi
    else
        panel_line "The datastore needs an existing directory - ideally a mounted disk."
    fi
    panel_bottom

    while true; do
        ask_required DS_NAME "Datastore name" "3-32 characters: letters, digits, . _ -" "${DS_NAME:-synology-backup}"
        if ! valid_ds_name "$DS_NAME"; then
            err "Use 3-32 characters: letters, digits, dot, underscore or dash (not starting with . or -)."
            continue
        fi
        if ds_exists "$DS_NAME"; then
            warn "A datastore called '${DS_NAME}' already exists on this server."
            menu_select choice 0 "Choose another name" "Keep the existing datastore - skip this step"
            if [[ $choice -eq 1 ]]; then
                DS_SKIP=1
                return 0
            fi
            continue
        fi
        break
    done

    if [[ $DS_REUSE -eq 1 ]]; then
        return 0
    fi

    if [[ $DO_ISCSI -eq 1 ]]; then
        while true; do
            ask_input DS_PATH "Datastore path" "press Enter for the suggested path" "$default_path"
            if [[ -z "$DS_PATH" ]]; then
                DS_PATH="$default_path"
            fi
            DS_PATH="${DS_PATH%/}"
            if [[ "$DS_PATH" == "$MOUNT_PATH" || "$DS_PATH" == "$MOUNT_PATH"/* ]]; then
                break
            fi
            err "The datastore path must be on the LUN (${MOUNT_PATH} or a folder below it)."
        done
    else
        while true; do
            ask_required DS_PATH "Datastore path" "e.g. /mnt/datastore/backup" "$DS_PATH"
            DS_PATH="${DS_PATH%/}"
            if [[ "$DS_PATH" != /* ]]; then
                err "The path must be absolute (start with /)."
                continue
            fi
            if mountpoint -q "$DS_PATH" 2>/dev/null; then
                break
            fi
            warn "${DS_PATH} is not a mount point - backups would land on the local system disk."
            if ask_yn "Use it anyway?" danger; then
                break
            fi
        done
    fi
}

setup_alerts() {
    local choice def=0
    case "$NOTIFY_MODE" in
        url)  def=1 ;;
        mail) def=2 ;;
    esac
    echo
    panel_top "Alerts from the monitor"
    panel_line "The monitor repairs a lost iSCSI connection by itself."
    panel_line "It can also tell you when something is wrong - and when it is fixed."
    panel_bottom
    while true; do
        menu_select choice "$def" \
            "No alerts|The monitor only writes to /var/log/iscsi-monitor.log" \
            "Push message / webhook|ntfy.sh, or any URL that accepts a plain POST request" \
            "Email|Sent with this server's sendmail / postfix"
        case "$choice" in
            0)
                NOTIFY_MODE="none"
                NOTIFY_URL=""
                NOTIFY_MAIL=""
                break
                ;;
            1)
                while true; do
                    ask_required NOTIFY_URL "Alert URL" "e.g. https://ntfy.sh/my-secret-topic  (keep the topic name secret)" "$NOTIFY_URL"
                    if [[ "$NOTIFY_URL" =~ ^https?://[^[:space:]]+$ ]]; then
                        break
                    fi
                    err "The URL must start with http:// or https:// and contain no spaces."
                done
                if ! command -v curl >/dev/null 2>&1; then
                    run_quiet "Installing curl" "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" install curl
                fi
                NOTIFY_MODE="url"
                NOTIFY_MAIL=""
                break
                ;;
            2)
                if ! command -v sendmail >/dev/null 2>&1; then
                    err "sendmail was not found on this server - set up postfix first, or use a push message."
                    continue
                fi
                while true; do
                    ask_required NOTIFY_MAIL "Email address" "where the alerts are sent" "$NOTIFY_MAIL"
                    if [[ "$NOTIFY_MAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
                        break
                    fi
                    err "That does not look like an email address."
                done
                NOTIFY_MODE="mail"
                NOTIFY_URL=""
                break
                ;;
        esac
    done
}

setup_mount_ds() {
    if [[ $DO_ISCSI -eq 0 && $DO_DS -eq 0 && $DO_MOTD -eq 0 ]]; then
        return 0
    fi
    render_setup 6
    if [[ $DO_ISCSI -eq 1 ]]; then
        if [[ "$DISK_ACTION" == "mounted" ]]; then
            MOUNT_PATH="$PROBE_MOUNTED_AT"
            if [[ $ADD_DRIVE -eq 1 && -f "/usr/local/bin/check-iscsi-session-$(basename "$MOUNT_PATH").sh" ]]; then
                err "This LUN is already set up as a drive (${MOUNT_PATH}). Nothing was changed."
                echo "  ${DIM}To add another drive, create a new LUN on the Synology and choose that one.${NC}"
                exit 0
            fi
            ok "The LUN stays mounted at ${MOUNT_PATH}"
        else
            ask_mount_path
        fi
    fi
    if [[ $DO_DS -eq 1 ]]; then
        setup_datastore_questions
    fi
    if [[ $DO_ISCSI -eq 1 ]]; then
        setup_alerts
    fi
    setup_motd
}

setup_motd() {
    local choice def=0 cur
    if [[ $DO_MOTD -ne 1 ]]; then
        return 0
    fi
    # an earlier choice (also made in pbs-menu > Settings) is the preselected one
    cur=$(motd_conf_val MODE)
    case "$cur" in dashboard|live|prompt) MOTD_MODE="$cur" ;; esac
    case "$MOTD_MODE" in dashboard) def=1 ;; live) def=2 ;; esac
    echo
    panel_top "Login screen"
    panel_line "When you log in you are met by a live dashboard: server health,"
    panel_line "the Synology connection, free space and the latest backups."
    panel_line "Press ${CYAN}m${NC} for a menu: live view, repair, logs, updates and help."
    panel_bottom
    menu_select choice "$def" \
        "Dashboard + menu prompt|After the dashboard press m for the menu - it waits 5 seconds, then your shell" \
        "Dashboard only|Shows the dashboard and your shell right away - the menu is still there as: pbs-menu" \
        "Live dashboard|Stays open and refreshes every 3 seconds until you press q - with a key bar (menu, log, repair, updates)"
    case "$choice" in
        1) MOTD_MODE="dashboard" ;;
        2) MOTD_MODE="live" ;;
        *) MOTD_MODE="prompt" ;;
    esac
}

setup_review() {
    local choice trim_txt="" lun_txt="" alert_txt=""
    render_setup 7
    panel_top "Your plan"
    kv "Repository" "$( [[ $DO_REPO -eq 1 ]] && echo 'switch to no-subscription' || echo 'unchanged' )"
    kv "Upgrade" "$( [[ $DO_UPGRADE -eq 1 ]] && echo 'apt full-upgrade' || echo 'no' )"
    if [[ $DO_ISCSI -eq 1 ]]; then
        kv "Synology" "$PORTAL_IP"
        kv "Target" "$TARGET_IQN"
        if [[ $CHAP_MODE -eq 1 ]]; then
            kv "Login" "CHAP · ${CHAP_USER} / ••••••••"
        else
            kv "Login" "no authentication"
        fi
        if [[ ${#LUN_DEVS[@]} -gt 1 ]]; then
            lun_txt=" · LUN ${LUN_NUM:-?} (1 of ${#LUN_DEVS[@]} on this target)"
        fi
        kv "LUN" "${LUN_SIZE_H} · $( case "$LUN_PROV" in thin) echo 'thin · weekly TRIM' ;; thin-off) echo 'thin · reclamation off' ;; thick) echo 'thick · no TRIM needed' ;; *) [[ $LUN_DISCARD -eq 1 ]] && echo 'TRIM supported' || echo 'no TRIM' ;; esac )${lun_txt}"
        case "$DISK_ACTION" in
            new)     kv "Disk" "${GREEN}create GPT partition + ${FS_TYPE}${NC}" ;;
            format)  kv "Disk" "${RED}ERASE the LUN and format it as ${FS_TYPE}${NC}" ;;
            keep)    kv "Disk" "${GREEN}keep the existing ${FS_TYPE} - no data is touched${NC}" ;;
            mounted) kv "Disk" "${GREEN}already mounted - unchanged${NC}" ;;
        esac
        kv "Mount path" "$MOUNT_PATH"
        if [[ $LUN_DISCARD -eq 1 ]]; then trim_txt=" · weekly TRIM"; fi
        kv "Monitoring" "health check + auto-repair every minute${trim_txt}"
        kv "Resilience" "waits $(( REPLACEMENT_TIMEOUT / 60 )) min for the NAS · PBS starts after the mount"
        case "$NOTIFY_MODE" in
            url)  alert_txt="push message / webhook ($(sed -E 's#^(https?://[^/]+).*#\1#' <<< "$NOTIFY_URL"))" ;;
            mail) alert_txt="email to ${NOTIFY_MAIL}" ;;
            *)    alert_txt="none - log file only" ;;
        esac
        kv "Alerts" "$alert_txt"
    else
        kv "iSCSI" "no"
    fi
    if [[ $DO_DS -eq 1 ]]; then
        if [[ $DS_SKIP -eq 1 ]]; then
            kv "Datastore" "'${DS_NAME}' already exists - unchanged"
        elif [[ $DS_REUSE -eq 1 ]]; then
            kv "Datastore" "${GREEN}re-attach${NC} '${DS_NAME}' at ${DS_PATH}"
        else
            kv "Datastore" "create '${DS_NAME}' at ${DS_PATH}"
        fi
    else
        kv "Datastore" "no"
    fi
    kv "Popup" "$( [[ $DO_NAG -eq 1 ]] && echo 'remove the subscription popup' || echo 'unchanged' )"
    kv "Login screen" "$( [[ $DO_MOTD -eq 1 ]] && case "$MOTD_MODE" in prompt) echo 'dashboard + menu prompt' ;; dashboard) echo 'dashboard only' ;; live) echo 'live dashboard (stays open until q)' ;; esac || echo 'unchanged' )"
    panel_bottom
    menu_select choice 0 \
        "Start the installation|Runs on its own from here - grab a coffee" \
        "Go back and change something|Your answers are kept as defaults" \
        "Quit|Nothing on any disk has been changed"
    case "$choice" in
        0) return 0 ;;
        1) return 1 ;;
        *) quit_clean ;;
    esac
}

run_setup() {
    if [[ $ADD_DRIVE -eq 0 ]]; then
        setup_welcome
    fi
    while true; do
        if [[ $ADD_DRIVE -eq 0 ]]; then
            setup_options
        fi
        if [[ $DO_ISCSI -eq 1 ]]; then
            setup_tools
            setup_synology_guide
            setup_connection
            setup_lun
        else
            DISK_ACTION=""
            PROBE_PBS=0
        fi
        setup_mount_ds
        if setup_review; then
            return 0
        fi
    done
}

# ===========================================================================
# INSTALLATION (unattended)
# ===========================================================================
step_repos() {
    local f
    if [[ $DO_REPO -ne 1 ]]; then
        skip_step $S_REPO "unchanged"
        return 0
    fi
    begin_step $S_REPO
    disable_enterprise_repos || ok "Enterprise repository already off"

    if grep -rqsE '^[[:space:]]*deb .*pbs-no-subscription' /etc/apt/sources.list /etc/apt/sources.list.d/ \
        || grep -rqsE '^Components:.*pbs-no-subscription' /etc/apt/sources.list.d/; then
        ok "No-subscription repository already present"
    elif [[ -f /usr/share/keyrings/proxmox-archive-keyring.gpg ]]; then
        cat > /etc/apt/sources.list.d/pbs-no-subscription.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: ${OS_CODENAME}
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
        ok "Added the no-subscription repository (deb822)"
    else
        echo "deb http://download.proxmox.com/debian/pbs ${OS_CODENAME} pbs-no-subscription" \
            > /etc/apt/sources.list.d/pbs-no-subscription.list
        ok "Added the no-subscription repository"
    fi
    APT_WARN=""
    apt_update
    finish_step $S_REPO "no-subscription enabled${APT_WARN:+ ($APT_WARN)}"
}

step_upgrade() {
    if [[ $DO_UPGRADE -ne 1 ]]; then
        skip_step $S_UPG "not requested"
        return 0
    fi
    begin_step $S_UPG
    if [[ $APT_UPDATED -eq 0 ]]; then
        apt_update
    fi
    run_quiet "Upgrading packages (this can take a few minutes)" \
        "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" full-upgrade
    NEED_REBOOT=1
    finish_step $S_UPG "packages upgraded"
}

step_connect() {
    local dev_size dev_wwn devs
    begin_step $S_CONN
    ensure_iscsi_service
    create_node_record
    apply_auth
    node_update node.startup automatic
    node_update node.session.timeo.replacement_timeout "$REPLACEMENT_TIMEOUT"
    ok "Only this target is set to log in automatically at boot"
    ok "Reconnect patience: $(( REPLACEMENT_TIMEOUT / 60 )) minutes ${DIM}(survives a Synology reboot or update)${NC}"

    if session_active; then
        ok "Session already active"
    else
        run_quiet_soft "Logging in to the target" \
            timeout 30 iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" --login
        if [[ $RUN_RC -ne 0 && $RUN_RC -ne 15 ]]; then
            fatal "Login failed (exit code ${RUN_RC}) even though the test during setup worked."
        fi
    fi

    if apply_live_timeout; then
        ok "The running session uses the longer reconnect patience right away"
    fi

    info "Waiting for the disk to appear..."
    devs=$(wait_for_devices) || devs=""
    if [[ -z "$devs" ]]; then
        fatal "Could not detect a running iSCSI disk for target ${TARGET_IQN}."
    fi
    DEVICE_PATH=$(pick_chosen_lun "$devs") || DEVICE_PATH=""
    if [[ -z "$DEVICE_PATH" ]]; then
        fatal "The LUN chosen during setup (${LUN_WWN:-LUN ${LUN_NUM:-?}}) is no longer offered by the target - stopping to protect your data."
    fi

    # Make sure this is the very same LUN that was inspected during setup
    dev_size=$(lsblk -dnbo SIZE "$DEVICE_PATH" 2>/dev/null | tr -d ' ' || true)
    dev_wwn=$(lsblk -dno WWN "$DEVICE_PATH" 2>/dev/null | tr -d ' ' || true)
    if [[ "$dev_size" != "$LUN_SIZE" || ( -n "$LUN_WWN" && "$dev_wwn" != "$LUN_WWN" ) ]]; then
        fatal "The LUN looks different from the one inspected during setup - stopping to protect your data."
    fi
    ok "LUN identity confirmed (${LUN_SIZE_H}${LUN_WWN:+, WWN $LUN_WWN})"
    finish_step $S_CONN "$DEVICE_PATH"
}

step_disk() {
    local p part_name attempt
    case "$DISK_ACTION" in
        mounted)
            PARTITION="$PROBE_NODE"
            UUID="$PROBE_UUID"
            skip_step $S_DISK "kept - already mounted"
            return 0
            ;;
        keep)
            begin_step $S_DISK
            PARTITION=$(blkid -U "$PROBE_UUID" 2>/dev/null || true)
            if [[ -z "$PARTITION" || ! -b "$PARTITION" ]]; then
                fatal "The existing filesystem (UUID ${PROBE_UUID}) was not found on the LUN."
            fi
            FS_TYPE=$(blkid -p -s TYPE -o value "$PARTITION" 2>/dev/null || echo "$PROBE_FS")
            UUID="$PROBE_UUID"
            ok "Keeping the existing ${FS_TYPE} filesystem on ${PARTITION}"
            finish_step $S_DISK "kept ${FS_TYPE} on ${PARTITION}"
            return 0
            ;;
    esac

    begin_step $S_DISK
    release_holders
    for p in $(lsblk -nlo NAME,TYPE "$DEVICE_PATH" | awk '$2 == "part" { print "/dev/" $1 }'); do
        wipefs -a "$p" >> "$LOG_FILE" 2>&1 || true
    done
    run_quiet "Removing old signatures" wipefs -a "$DEVICE_PATH"
    run_quiet "Creating GPT partition table" parted -s "$DEVICE_PATH" mklabel gpt
    run_quiet "Creating partition" parted -s -a optimal "$DEVICE_PATH" mkpart "$FS_LABEL" "$FS_TYPE" 0% 100%
    partprobe "$DEVICE_PATH" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true

    PARTITION=""
    for attempt in $(seq 1 10); do
        part_name=$(lsblk -nlo NAME,TYPE "$DEVICE_PATH" | awk '$2 == "part" { print $1; exit }')
        if [[ -n "$part_name" && -b "/dev/$part_name" ]]; then
            PARTITION="/dev/$part_name"
            break
        fi
        sleep 1
    done
    if [[ -z "$PARTITION" ]]; then
        fatal "The partition was not created on ${DEVICE_PATH}."
    fi

    if [[ "$FS_TYPE" == "xfs" ]]; then
        run_quiet "Formatting ${PARTITION} as XFS" mkfs.xfs -f -K -L "$FS_LABEL" "$PARTITION"
    else
        run_quiet "Formatting ${PARTITION} as ext4" \
            mkfs.ext4 -F -m 0 -E nodiscard -L "$FS_LABEL" "$PARTITION"
    fi
    udevadm settle >/dev/null 2>&1 || true

    UUID=$(blkid -p -s UUID -o value "$PARTITION" 2>/dev/null || true)
    if [[ -z "$UUID" ]]; then
        fatal "Cannot determine the UUID of ${PARTITION}"
    fi
    finish_step $S_DISK "${FS_TYPE} on ${PARTITION}"
}

step_mount() {
    local unit unit_name tmp_fstab service_name current
    begin_step $S_MOUNT
    FSTAB_ENTRY="UUID=${UUID} ${MOUNT_PATH} ${FS_TYPE} defaults,_netdev,nofail,x-systemd.device-timeout=30 0 0"

    if [[ "$DISK_ACTION" == "mounted" ]]; then
        # v1.5: also correct an existing line written by an older version
        current=$(awk -v p="$MOUNT_PATH" '!/^[[:space:]]*#/ && $2 == p' /etc/fstab | head -n 1)
        if [[ "$current" == "$FSTAB_ENTRY" ]]; then
            ok "Already mounted and /etc/fstab is correct"
        else
            cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
            tmp_fstab=$(mktemp)
            awk -v p="$MOUNT_PATH" '/^[[:space:]]*#/ || $2 != p' /etc/fstab > "$tmp_fstab"
            cat "$tmp_fstab" > /etc/fstab
            rm -f "$tmp_fstab"
            echo "$FSTAB_ENTRY" >> /etc/fstab
            systemctl daemon-reload
            if [[ -n "$current" ]]; then
                ok "Updated the /etc/fstab entry to the current format (backup saved)"
            else
                ok "Added the missing /etc/fstab entry (backup saved)"
            fi
        fi
        finish_step $S_MOUNT "$MOUNT_PATH (already mounted)"
        return 0
    fi

    service_name=$(basename "$MOUNT_PATH")
    mkdir -p "$MOUNT_PATH"

    # Remove stale systemd units left over from older versions of this script
    for unit in \
        "/etc/systemd/system/mnt-datastore-${service_name}.mount" \
        "/etc/systemd/system/mnt-datastore-${service_name}.automount" \
        "/etc/systemd/system/$(systemd-escape --path --suffix=mount "$MOUNT_PATH")" \
        "/etc/systemd/system/$(systemd-escape --path --suffix=automount "$MOUNT_PATH")"; do
        if [[ -f "$unit" ]]; then
            unit_name=$(basename "$unit")
            systemctl stop "$unit_name" 2>/dev/null || true
            systemctl disable "$unit_name" 2>/dev/null || true
            rm -f "$unit"
        fi
    done

    if mountpoint -q "$MOUNT_PATH"; then
        fatal "${MOUNT_PATH} was mounted by something else after setup - stopping."
    fi

    cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
    # Remove existing entries for exactly this mount point (2nd field); keep comments
    tmp_fstab=$(mktemp)
    awk -v p="$MOUNT_PATH" '/^[[:space:]]*#/ || $2 != p' /etc/fstab > "$tmp_fstab"
    cat "$tmp_fstab" > /etc/fstab
    rm -f "$tmp_fstab"
    echo "$FSTAB_ENTRY" >> /etc/fstab
    ok "fstab entry written (backup saved)"
    systemctl daemon-reload

    # While nothing is mounted, make the bare directory immutable so nothing
    # (e.g. PBS) can ever write into it on the local disk if the mount is missing.
    chattr +i "$MOUNT_PATH" 2>/dev/null || warn "Could not set the immutable flag on ${MOUNT_PATH}"

    run_quiet "Mounting ${MOUNT_PATH}" mount "$MOUNT_PATH"
    if ! mountpoint -q "$MOUNT_PATH"; then
        fatal "Mount failed"
    fi
    finish_step $S_MOUNT "$MOUNT_PATH ($(df -h --output=size "$MOUNT_PATH" | tail -n 1 | tr -d ' '))"
}

# Writes the monitor script to $1. Target, portal and mount path are baked in;
# the alert settings live in a separate root-only config file.
write_monitor_script() {
    local dest="$1" service_name
    service_name=$(basename "$MOUNT_PATH")
    {
        echo '#!/bin/bash'
        echo "# Auto-generated iSCSI session, mount and health monitor for $service_name (pbs-post-install v${VERSION})"
        printf 'TARGET=%q\n' "$TARGET_IQN"
        printf 'PORTAL=%q\n' "$PORTAL_IP"
        printf 'MOUNT_PATH=%q\n' "$MOUNT_PATH"
        printf 'LOCK_FILE=%q\n' "/run/lock/iscsi-monitor-${service_name}.lock"
        printf 'STATE_FILE=%q\n' "/run/iscsi-monitor-${service_name}.state"
        printf 'CONF_FILE=%q\n' "/etc/pbs-iscsi-monitor-${service_name}.conf"
        cat <<'MONITOR_EOF'
LOG_FILE="/var/log/iscsi-monitor.log"
WRITE_TEST_SECS=20      # a write that takes longer = the storage is not answering
REPAIR_COOLDOWN=300     # at most one automatic repair every 5 minutes
RESTART_PBS=1           # restart the PBS services after a successful repair
AUTH_RETRY=900          # after a rejected login (wrong/missing CHAP) try only every 15 minutes
NOTIFY_MODE="none"
NOTIFY_URL=""
NOTIFY_MAIL=""
# shellcheck disable=SC1090
[ -r "$CONF_FILE" ] && . "$CONF_FILE"
AUTH_FILE="${STATE_FILE}.authfail"

# Never run two copies at once (cron fires every minute). A write test that is
# stuck on dead storage keeps this lock, so runs can never pile up behind it.
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

notify() {
    case "$NOTIFY_MODE" in
        url)
            if [ -n "$NOTIFY_URL" ]; then
                timeout 20 curl -fsS -m 15 -H "Title: $1" -d "$2" "$NOTIFY_URL" >/dev/null 2>&1 \
                    || log_message "Could not send the alert (webhook)"
            fi
            ;;
        mail)
            if [ -n "$NOTIFY_MAIL" ]; then
                printf 'To: %s\nSubject: %s\n\n%s\n' "$NOTIFY_MAIL" "$1" "$2" | timeout 20 sendmail -t >/dev/null 2>&1 \
                    || log_message "Could not send the alert (email)"
            fi
            ;;
    esac
    return 0
}

# Exact IQN match (field 4 of "iscsiadm -m session")
session_present() {
    timeout 20 iscsiadm -m session 2>/dev/null | awk -v t="$TARGET" '$4 == t { f = 1 } END { exit !f }'
}

# Logs in. 0 = connected, 24 = the Synology rejected the login (authentication),
# anything else = failed. A rejected login is NOT retried every minute: repeating
# a wrong password floods the Synology's log and can lock the account.
do_login() {
    local rc=0 out
    out=$(timeout 30 iscsiadm -m node -T "$TARGET" -p "$PORTAL" --login 2>&1) || rc=$?
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 15 ]; then
        rm -f "$AUTH_FILE"
        return 0
    fi
    if [ "$rc" -eq 24 ] || printf '%s' "$out" | grep -qiE 'authentication failed|authorization failure|failed to authenticate'; then
        date +%s > "$AUTH_FILE"
        log_message "Login REJECTED by the Synology: the stored CHAP username/password is missing or wrong."
        log_message "Not retrying for $(( AUTH_RETRY / 60 )) minutes. Fix it with:  pbs-post-install.sh --fix-login  (or run the installer with --fix-login)"
        return 24
    fi
    return 1
}

# findmnt only reads /proc/self/mountinfo, so it can never hang on dead storage
is_mounted() {
    findmnt -rn -M "$MOUNT_PATH" >/dev/null 2>&1
}

mount_is_readonly() {
    local o
    o=$(findmnt -rn -M "$MOUNT_PATH" -o OPTIONS 2>/dev/null)
    case ",${o}," in
        *,ro,*) return 0 ;;
    esac
    return 1
}

# Creates, syncs and removes a small file on the LUN.
# 0 = ok, 2 = the write failed, 3 = no answer within WRITE_TEST_SECS
write_test() {
    local f="$MOUNT_PATH/.pbs-monitor-test" pid i
    ( : > "$f" && sync -d "$f" && rm -f "$f" ) 2>/dev/null &
    pid=$!
    for i in $(seq 1 "$WRITE_TEST_SECS"); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        return 3
    fi
    if wait "$pid"; then
        return 0
    fi
    return 2
}

# 0 = healthy, 1 = storage not answering (wait: a repair would hang too), 2 = broken
check_health() {
    local rc=0
    if ! is_mounted; then
        return 2
    fi
    if mount_is_readonly; then
        log_message "$MOUNT_PATH is mounted read-only (the filesystem hit an I/O error)"
        return 2
    fi
    write_test || rc=$?
    case "$rc" in
        0) return 0 ;;
        3)
            log_message "Write test on $MOUNT_PATH got no answer within ${WRITE_TEST_SECS}s - the Synology may be restarting"
            return 1
            ;;
        *)
            log_message "Write test on $MOUNT_PATH failed"
            return 2
            ;;
    esac
}

repair() {
    local now last i
    now=$(date +%s)
    last=$(cat "${STATE_FILE}.repair" 2>/dev/null || echo 0)
    if [ $(( now - last )) -lt "$REPAIR_COOLDOWN" ]; then
        log_message "Repair skipped - the last attempt was less than $(( REPAIR_COOLDOWN / 60 )) minutes ago"
        return 1
    fi
    echo "$now" > "${STATE_FILE}.repair"
    log_message "Repairing: unmount > logout > login > mount"
    if is_mounted; then
        timeout -k 5 60 umount "$MOUNT_PATH" >/dev/null 2>&1 \
            || timeout -k 5 30 umount -l "$MOUNT_PATH" >/dev/null 2>&1
    fi
    timeout 30 iscsiadm -m node -T "$TARGET" -p "$PORTAL" --logout >/dev/null 2>&1
    sleep 2
    if ! do_login; then
        log_message "Repair failed: could not log in to $TARGET"
        return 1
    fi
    udevadm settle --timeout=20 >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if timeout -k 5 60 mount "$MOUNT_PATH" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done
    if ! is_mounted || mount_is_readonly; then
        log_message "Repair failed: $MOUNT_PATH could not be mounted read-write"
        return 1
    fi
    log_message "Repair succeeded: $MOUNT_PATH is mounted again"
    if [ "$RESTART_PBS" = "1" ]; then
        if timeout 90 systemctl restart proxmox-backup proxmox-backup-proxy >/dev/null 2>&1; then
            log_message "Restarted the PBS services"
        else
            log_message "Could not restart the PBS services"
        fi
    fi
    notify "PBS storage repaired on $(hostname)" "The iSCSI connection to $TARGET was repaired automatically and $MOUNT_PATH is mounted again."
    return 0
}

problem=0

if ! session_present; then
    last_auth=$(cat "$AUTH_FILE" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - last_auth )) -lt "$AUTH_RETRY" ]; then
        # The login was rejected recently - stay quiet and do not try again yet
        problem=1
    else
        log_message "iSCSI session for $TARGET not found. Attempting to reconnect..."
        # Timeout so a login to an unreachable Synology can never block the monitor
        if do_login; then
            log_message "Successfully reconnected to $TARGET"
            udevadm settle --timeout=20 >/dev/null 2>&1
            sleep 2
        else
            log_message "Failed to reconnect to $TARGET"
            problem=1
        fi
    fi
else
    rm -f "$AUTH_FILE"
    # Session exists - "iSCSI Session State: LOGGED_IN" when healthy
    session_state=$(timeout 20 iscsiadm -m session -P 3 2>/dev/null | awk -v t="$TARGET" '
        /^[[:space:]]*Target:/ { in_t = ($2 == t) }
        in_t && /iSCSI Session State:/ { print $NF; exit }
    ')
    if [ -n "$session_state" ] && [ "$session_state" != "LOGGED_IN" ]; then
        log_message "iSCSI session for $TARGET exists but state is $session_state"
    fi
fi

if [ "$problem" -eq 0 ] && ! is_mounted; then
    log_message "Mount point $MOUNT_PATH not mounted. Attempting to mount..."
    # Timeout so a hanging mount can never block the monitor
    if timeout -k 5 60 mount "$MOUNT_PATH" >/dev/null 2>&1; then
        log_message "Successfully mounted $MOUNT_PATH"
    else
        log_message "Failed to mount $MOUNT_PATH"
        problem=1
    fi
fi

if [ "$problem" -eq 0 ]; then
    check_health
    case $? in
        0) ;;
        1) problem=1 ;;
        *) repair || problem=1 ;;
    esac
fi

# Alerts only when the state changes (no message every minute)
prev=$(cat "$STATE_FILE" 2>/dev/null || echo ok)
if [ "$problem" -eq 1 ]; then cur=bad; else cur=ok; fi
echo "$cur" > "$STATE_FILE"
if [ "$prev" = "ok" ] && [ "$cur" = "bad" ]; then
    notify "PBS storage problem on $(hostname)" "The iSCSI storage ($TARGET, mounted at $MOUNT_PATH) is not responding or could not be reconnected. Details: $LOG_FILE"
elif [ "$prev" = "bad" ] && [ "$cur" = "ok" ]; then
    log_message "Storage is healthy again"
    notify "PBS storage recovered on $(hostname)" "The iSCSI storage ($TARGET) is healthy again."
fi
MONITOR_EOF
    } > "$dest"
}

# Sends one test message with the alert settings chosen in setup
send_test_alert() {
    local text="Test alert from ${HOST_NAME:-this server}: the iSCSI monitor can reach you."
    case "$NOTIFY_MODE" in
        url)
            timeout 20 curl -fsS -m 15 -H "Title: PBS installer test" -d "$text" "$NOTIFY_URL" >/dev/null 2>&1
            ;;
        mail)
            printf 'To: %s\nSubject: %s\n\n%s\n' "$NOTIFY_MAIL" "PBS installer test" "$text" \
                | timeout 20 sendmail -t >/dev/null 2>&1
            ;;
        *) return 0 ;;
    esac
}

# The crontab without the monitor line of one drive (exact name: "synology" never matches "synology2")
cron_without_monitor() {
    crontab -l 2>/dev/null | awk -v s="# iSCSI monitor for $1" '
        !(length($0) >= length(s) && substr($0, length($0) - length(s) + 1) == s)' || true
}

step_monitor() {
    local service_name cron_job tmp_cron detail="health check + auto-repair every minute"
    local mount_unit svc dir conf
    begin_step $S_MON
    service_name=$(basename "$MOUNT_PATH")
    CHECK_ISCSI_SCRIPT="/usr/local/bin/check-iscsi-session-${service_name}.sh"
    write_monitor_script "$CHECK_ISCSI_SCRIPT"
    chmod +x "$CHECK_ISCSI_SCRIPT"

    cron_job="*/1 * * * * $CHECK_ISCSI_SCRIPT # iSCSI monitor for $service_name"
    tmp_cron=$(mktemp)
    cron_without_monitor "$service_name" > "$tmp_cron" || true
    echo "$cron_job" >> "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"
    ok "Monitor installed: ${CHECK_ISCSI_SCRIPT}"
    ok "It checks the session, the mount and a test write - and repairs by itself"

    # Alert settings (root-only file; the URL may contain a secret topic name)
    conf="/etc/pbs-iscsi-monitor-${service_name}.conf"
    (
        umask 077
        {
            printf 'NOTIFY_MODE=%q\n' "$NOTIFY_MODE"
            printf 'NOTIFY_URL=%q\n' "$NOTIFY_URL"
            printf 'NOTIFY_MAIL=%q\n' "$NOTIFY_MAIL"
        } > "$conf"
    )
    chmod 600 "$conf"
    if [[ "$NOTIFY_MODE" != "none" ]]; then
        if send_test_alert; then
            ok "Test alert sent - check that it arrived"
            detail+=" · alerts on"
        else
            warn "The test alert could not be sent - check the address and this server's internet / mail setup"
        fi
    fi

    cat > /etc/logrotate.d/pbs-iscsi-monitor <<'LOGROTATE_EOF'
/var/log/iscsi-monitor.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
}
LOGROTATE_EOF
    ok "Monitor log rotation: weekly, 8 weeks kept"

    # Start PBS only after the iSCSI mount has been tried. "Wants" (not "Requires"),
    # so a dead NAS never keeps PBS - and its web UI - from starting.
    mount_unit=$(systemd-escape --path --suffix=mount "$MOUNT_PATH")
    for svc in proxmox-backup proxmox-backup-proxy; do
        dir="/etc/systemd/system/${svc}.service.d"
        mkdir -p "$dir"
        cat > "${dir}/10-iscsi-${service_name}.conf" <<EOF
# Written by pbs-post-install: start PBS after the iSCSI disk is mounted.
[Unit]
Wants=${mount_unit}
After=${mount_unit}
EOF
    done
    systemctl daemon-reload
    ok "PBS now starts after ${MOUNT_PATH} is mounted ${DIM}(boot order)${NC}"
    detail+=" · boot order"

    # Keep a copy of this script, so "--status" works from anywhere
    SELF_CMD="re-run the installer with --status"
    if [[ -f "$0" ]]; then
        if [[ "$0" -ef /usr/local/sbin/pbs-post-install.sh ]] || cp "$0" /usr/local/sbin/pbs-post-install.sh 2>/dev/null; then
            chmod 755 /usr/local/sbin/pbs-post-install.sh
            SELF_CMD="pbs-post-install.sh --status"
        fi
    fi

    if [[ $LUN_DISCARD -eq 1 ]]; then
        run_quiet_soft "Enabling weekly TRIM (space reclamation)" systemctl enable --now fstrim.timer
        if [[ $RUN_RC -eq 0 ]]; then
            detail+=" · weekly TRIM"
        fi
        if [[ "$DISK_ACTION" == "keep" || "$DISK_ACTION" == "format" ]]; then
            # The first TRIM of an existing filesystem can take a long time over iSCSI,
            # so it runs in the background instead of holding up the installer
            if systemctl start --no-block fstrim.service >/dev/null 2>&1; then
                note "Unused space is being given back to the Synology in the background (can take a while). Check: systemctl status fstrim.service"
                detail+=" · first TRIM running"
            fi
        fi
    fi
    finish_step $S_MON "$detail"
}

# ===========================================================================
# LOGIN SCREEN (MOTD)  - dashboard + menu shown when someone logs in
# ===========================================================================
write_motd_script() {
    local dest="$1"
    {
        echo '#!/bin/bash'
        # before the first command, so it covers the whole file: the screens are started
        # indirectly (page_run screen_lun), which ShellCheck reads as "unreachable"
        echo '# shellcheck disable=SC2317'
        printf 'PBS_MOTD_VERSION=%q\n' "$VERSION"
        cat <<'MOTD_EOF'
# pbs-motd - login dashboard, live view and menu for Proxmox Backup Server.
# Written by pbs-post-install. Read-only: it never changes storage by itself.
#   pbs-motd              show the dashboard
#   pbs-motd --login      what runs at login (honours MODE in /etc/pbs-motd.conf)
#   pbs-motd --watch      live view, refreshes every 3 seconds
#   pbs-motd --update-installer   install the newest release (asks first)
#   pbs-motd --rollback   go back to the version before the last update
#   pbs-motd --menu       interactive menu   (also: pbs-menu)
#   pbs-motd --help       key commands       (also: pbs-help)
export LC_ALL=C.UTF-8
CONF=/etc/pbs-motd.conf
MODE="prompt"          # off | dashboard | prompt | live
PROMPT_SECS=5
UPDATE_PROMPT=1        # 1 = at login, offer to install available updates
UPDATE_CHECK=1         # 1 = look once a day on GitHub for a newer version of this installer
AUTO_UPDATE=0          # 1 = also install a newer version by itself (off by default)
REFRESH_SECS=3         # live dashboard: seconds between redraws
if [ -r "$CONF" ] && [ "$(stat -c %u "$CONF" 2>/dev/null)" = "0" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi
INSTALLER=/usr/local/sbin/pbs-post-install.sh
DS_CFG="${DS_CFG:-/etc/proxmox-backup/datastore.cfg}"
TASK_DIR=/var/log/proxmox-backup/tasks
MON_LOG=/var/log/iscsi-monitor.log
UPD_FILE=/var/lib/pbs-motd/updates
REL_FILE=/var/lib/pbs-motd/release
BACKUP_DIR=/var/lib/pbs-motd/backup
UPD_LOG=/var/log/pbs-motd-update.log
GH_REPO="${GH_REPO:-MorphyDK/pbs-synology-iscsi}"
SNOOZE_FILE=/var/lib/pbs-motd/snooze
BOOT_DIR="${BOOT_DIR:-/boot}"

# ---------------------------------------------------------------- colours
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\e[1;31m'; GREEN=$'\e[1;32m'; YELLOW=$'\e[1;33m'; BLUE=$'\e[1;34m'
    CYAN=$'\e[1;36m'; WHITE=$'\e[1;37m'; DIM=$'\e[2m'; NC=$'\e[0m'
    ALERT=$'\e[1;5;97;41m'      # bold, blinking where the terminal supports it, white on sharp red
    if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]; then
        GRAD=($'\e[38;5;51m' $'\e[38;5;45m' $'\e[38;5;39m' $'\e[38;5;33m' $'\e[38;5;27m' $'\e[38;5;21m')
    else
        GRAD=("$CYAN" "$CYAN" "$CYAN" "$BLUE" "$BLUE" "$BLUE")
    fi
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; WHITE=""; DIM=""; NC=""; ALERT=""
    GRAD=("" "" "" "" "" "")
fi
PANEL_C="$BLUE"
PROBLEMS=0
WARNINGS=0

term_cols() {
    local c
    c=$(tput cols 2>/dev/null || echo 80)
    case "$c" in ''|*[!0-9]*) c=80 ;; esac
    echo "$c"
}
COLS=$(term_cols)

trunc() {
    local s="$1" w="$2"
    [ "$w" -lt 4 ] && w=4
    if [ "${#s}" -gt "$w" ]; then printf '%s…' "${s:0:w-1}"; else printf '%s' "$s"; fi
}

panel_top()    { PANEL_C="${2:-$BLUE}"; printf '  %s╭─%s %s%s%s\n' "$PANEL_C" "$NC" "$WHITE" "$1" "$NC"; }
panel_line()   { printf '  %s│%s %s\n' "$PANEL_C" "$NC" "$*"; }
panel_blank()  { printf '  %s│%s\n' "$PANEL_C" "$NC"; }
panel_bottom() { printf '  %s╰─%s\n' "$PANEL_C" "$NC"; PANEL_C="$BLUE"; }
kv()           { printf '  %s│%s %s%-14s%s %s\n' "$PANEL_C" "$NC" "$DIM" "$1" "$NC" "$2"; }
st_info() { kv "$1" "$2"; }
st_good() { kv "$1" "${GREEN}✔${NC} $2"; }
st_warn() { kv "$1" "${YELLOW}⚠ $2${NC}"; WARNINGS=$(( WARNINGS + 1 )); }
st_bad()  { kv "$1" "${RED}✘ $2${NC}"; PROBLEMS=$(( PROBLEMS + 1 )); }

uptime_secs() { cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1; }

# Like st_bad, but only a warning in the first minutes after a boot: the iSCSI link and the
# mount are still being set up (the monitor connects them within a minute)
st_down() {
    if [ "$(uptime_secs)" -lt 240 ]; then
        st_warn "$1" "$2  ${DIM}(just booted - connecting, refresh in a minute)${NC}"
    else
        st_bad "$1" "$2"
    fi
}

# thin | thin-off | thick | unknown  (see pbs-post-install.sh, lun_provisioning)
lun_provisioning() {
    local d="$1" mode b6 type=0
    mode=$(cat /sys/block/"${d}"/device/scsi_disk/*/provisioning_mode 2>/dev/null | head -n 1)
    read -r _ b6 < <(od -An -tu1 -j5 -N2 "/sys/block/${d}/device/vpd_pgb2" 2>/dev/null)
    case "${b6:-}" in ''|*[!0-9]*) ;; *) type=$(( b6 & 7 )) ;; esac
    if [ "$type" -eq 1 ]; then echo thick
    elif [ "$mode" = "unmap" ]; then echo thin
    elif [ "$type" -eq 2 ]; then echo thin-off
    elif [ -n "$mode" ]; then echo thick
    else echo unknown; fi
}

# bar PERCENT [WIDTH]   yellow from 85 %, red from 95 %
bar() {
    local pct="$1" width="${2:-24}" filled colour="$GREEN" full empty
    case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
    [ "$pct" -gt 100 ] && pct=100
    filled=$(( pct * width / 100 ))
    if [ "$pct" -ge 95 ]; then colour="$RED"; elif [ "$pct" -ge 85 ]; then colour="$YELLOW"; fi
    full=$(printf '%*s' "$filled" '' | sed 's/ /█/g')
    empty=$(printf '%*s' $(( width - filled )) '' | sed 's/ /░/g')
    printf '%s%s%s%s%s %s%3d%%%s' "$colour" "$full" "$DIM" "$empty" "$NC" "$colour" "$pct" "$NC"
}

hb() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

age() {   # seconds -> "5m ago"
    local s="$1"
    if [ "$s" -lt 90 ]; then echo "${s}s ago"
    elif [ "$s" -lt 5400 ]; then echo "$(( (s + 30) / 60 ))m ago"
    elif [ "$s" -lt 129600 ]; then echo "$(( (s + 1800) / 3600 ))h ago"
    else echo "$(( s / 86400 ))d ago"; fi
}

# ---------------------------------------------------------------- data
SESS1=""; SESS3=""
gather_sessions() {
    SESS1=$(timeout 10 iscsiadm -m session 2>/dev/null)
    SESS3=$(timeout 10 iscsiadm -m session -P 3 2>/dev/null)
}

# ---------------------------------------------------------------- updates
# Cache file: COUNT|TIMESTAMP|IMPORTANT(0/1)|first package names.
# Written by the apt hook after every apt update / dpkg run, daily by cron, and again at
# login when dpkg or apt changed since it was written - so it never shows old news.
refresh_updates() {
    local raw out n imp names
    mkdir -p "$(dirname "$UPD_FILE")"
    raw=$(timeout 30 apt-get -s dist-upgrade 2>/dev/null) || return 0
    out=$(awk '/^Inst /{print $2}' <<< "$raw")
    n=0
    [ -n "$out" ] && n=$(printf '%s\n' "$out" | wc -l)
    imp=0
    if printf '%s\n' "$out" | grep -Eq '^(proxmox-kernel|pve-kernel|linux-image|proxmox-backup-server$|libc6$|systemd$|udev$)'; then
        imp=1
    fi
    names=$(printf '%s\n' "$out" | head -n 6 | paste -sd, -)
    [ "$n" -gt 6 ] && names="${names},…"
    echo "${n}|$(date +%s)|${imp}|${names}" > "$UPD_FILE"
}

UPD_N=""; UPD_STAMP=0; UPD_IMP=0; UPD_NAMES=""
load_updates() {
    local mt
    UPD_N=""; UPD_STAMP=0; UPD_IMP=0; UPD_NAMES=""
    mt=$(stat -c %Y "$UPD_FILE" 2>/dev/null || echo 0)
    if [ "$(id -u)" -eq 0 ]; then
        if [ ! -r "$UPD_FILE" ] || [ /var/lib/dpkg/status -nt "$UPD_FILE" ] \
            || [ /var/lib/apt/lists -nt "$UPD_FILE" ] || [ $(( $(date +%s) - mt )) -gt 21600 ]; then
            refresh_updates
        fi
    fi
    if [ -r "$UPD_FILE" ]; then
        IFS='|' read -r UPD_N UPD_STAMP UPD_IMP UPD_NAMES < "$UPD_FILE"
    fi
    case "$UPD_N" in ''|*[!0-9]*) UPD_N="" ;; esac
    return 0
}

# Is a newer kernel installed than the one that is running?
REBOOT_NEEDED=0; RUNNING_K=""; INSTALLED_K=""
reboot_info() {
    local newest
    RUNNING_K=$(uname -r)
    # shellcheck disable=SC2012
    newest=$(ls -1 "$BOOT_DIR"/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -n 1)
    INSTALLED_K="${newest:-$RUNNING_K}"
    REBOOT_NEEDED=0
    [ -f /var/run/reboot-required ] && REBOOT_NEEDED=1
    if [ "$(printf '%s\n%s\n' "$RUNNING_K" "$INSTALLED_K" | sort -V | tail -n 1)" != "$RUNNING_K" ]; then
        REBOOT_NEEDED=1
    fi
    return 0
}

# ---------------------------------------------------------------- installer updates
# Once a day (cron, or in the background at login when the cache is old) the newest release
# tag is read from GitHub: one small request to api.github.com, nothing is sent about you.
# Cache file: LATEST|LAST_OK|LAST_TRY   (seconds since 1970)
ver_gt() {   # ver_gt A B -> true when A is a newer version than B
    [ -n "$1" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

http_get() {   # http_get URL  -> body on stdout
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 25 -H 'User-Agent: pbs-motd' "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=25 --user-agent=pbs-motd "$1"
    else
        return 127
    fi
}

check_release() {
    local json new tag ok now
    now=$(date +%s)
    mkdir -p "$(dirname "$REL_FILE")"
    tag=""; ok=0
    [ -r "$REL_FILE" ] && IFS='|' read -r tag ok _ < "$REL_FILE"
    json=$(http_get "https://api.github.com/repos/${GH_REPO}/releases/latest" 2>/dev/null) || json=""
    new=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$json" | head -n 1)
    new=${new#v}
    case "$new" in
        [0-9]*) echo "${new}|${now}|${now}" > "$REL_FILE"; return 0 ;;
    esac
    echo "${tag:-}|${ok:-0}|${now}" > "$REL_FILE"
    return 1
}

REL_LATEST=""; REL_NEW=0; REL_OK=0; REL_TRY=0; REL_SKIPPED=0
load_release() {
    local now skip
    REL_LATEST=""; REL_NEW=0; REL_OK=0; REL_TRY=0; REL_SKIPPED=0
    [ "$UPDATE_CHECK" = "1" ] || [ "${1:-}" = "force" ] || return 0
    [ -r "$REL_FILE" ] && IFS='|' read -r REL_LATEST REL_OK REL_TRY < "$REL_FILE"
    case "$REL_OK" in ''|*[!0-9]*) REL_OK=0 ;; esac
    case "$REL_TRY" in ''|*[!0-9]*) REL_TRY=0 ;; esac
    skip=$(cat "$BACKUP_DIR/skip" 2>/dev/null)
    if ver_gt "$REL_LATEST" "${PBS_MOTD_VERSION:-0}"; then
        if [ "$REL_LATEST" = "$skip" ]; then REL_SKIPPED=1; else REL_NEW=1; fi
    fi
    # Cache older than a day (the server was off at the cron hour)? Look again in the background
    if [ "$(id -u)" -eq 0 ] && [ "$UPDATE_CHECK" = "1" ]; then
        now=$(date +%s)
        if [ $(( now - REL_OK )) -gt 90000 ] && [ $(( now - REL_TRY )) -gt 21600 ]; then
            echo "${REL_LATEST}|${REL_OK}|${now}" > "$REL_FILE" 2>/dev/null
            ( timeout 60 /usr/local/sbin/pbs-motd --check-release </dev/null >/dev/null 2>&1 & )
        fi
    fi
    return 0
}

ulog() {   # ulog "text" - screen unless quiet, and the log file
    [ "${QUIET_UPDATE:-0}" = "1" ] || echo "  $*"
    # shellcheck disable=SC2001
    printf '%s %s\n' "$(date '+%F %T')" "$(sed 's/\x1b\[[0-9;]*m//g' <<< "$*")" >> "$UPD_LOG" 2>/dev/null
    return 0
}

restore_version() {   # restore_version VERSION - copy the saved files back (atomic rename)
    local v="$1" name
    for name in pbs-motd pbs-post-install.sh; do
        if [ -f "$BACKUP_DIR/$name.$v" ]; then
            cp -p "$BACKUP_DIR/$name.$v" "/usr/local/sbin/$name.new" \
                && mv -f "/usr/local/sbin/$name.new" "/usr/local/sbin/$name"
        fi
    done
    if [ -f "$BACKUP_DIR/pbs-motd.conf.$v" ]; then
        cp -p "$BACKUP_DIR/pbs-motd.conf.$v" "$CONF"
    fi
}

prune_backups() {   # keep the 3 newest saved versions
    local f
    for f in pbs-motd pbs-motd.conf pbs-post-install.sh; do
        # shellcheck disable=SC2012
        ls -1t "$BACKUP_DIR/$f".[0-9]* 2>/dev/null | tail -n +4 | xargs -r rm -f
    done
}

# installer_update [auto]  - download, check, install; goes back by itself when anything fails
UPDATED=0
installer_update() {
    local mode="${1:-ask}" old="${PBS_MOTD_VERSION:-0}" tmp url tag fver got=0 inst=/usr/local/sbin
    UPDATED=0
    QUIET_UPDATE=0; [ "$mode" = auto ] && QUIET_UPDATE=1
    need_root || return 1
    exec 9>/var/lock/pbs-motd-update.lock
    flock -n 9 || { ulog "${YELLOW}Another update is running.${NC}"; return 1; }
    if [ "$mode" != auto ]; then
        echo
        printf '  %sLooking for a newer version…%s' "$DIM" "$NC"
        if ! check_release; then
            printf '\r\e[K'
            ulog "${YELLOW}⚠ Could not reach GitHub (https://github.com/${GH_REPO}). Try again later.${NC}"
            return 1
        fi
        printf '\r\e[K'
    fi
    load_release force
    if [ -z "$REL_LATEST" ]; then
        ulog "${YELLOW}⚠ Could not reach GitHub (https://github.com/${GH_REPO}). Try again later.${NC}"
        return 1
    fi
    if ! ver_gt "$REL_LATEST" "$old"; then
        ulog "${GREEN}✔ You have the newest version (v${old}).${NC}"
        return 0
    fi
    if [ "$mode" != auto ]; then
        echo
        panel_top "New version of this installer" "$YELLOW"
        kv "Installed" "v${old}"
        kv "Available" "${WHITE}v${REL_LATEST}${NC}"
        kv "Release notes" "${DIM}https://github.com/${GH_REPO}/releases${NC}"
        panel_blank
        panel_line "Only the login screen and the installer script are replaced."
        panel_line "${DIM}Your iSCSI connection, mount, datastores and backups are not touched.${NC}"
        panel_line "${DIM}The current version is saved first - pbs-motd --rollback goes back.${NC}"
        panel_bottom
        ask_yn "Install v${REL_LATEST} now?" || { echo "  ${DIM}Nothing was changed.${NC}"; return 0; }
    fi
    tmp=$(mktemp /tmp/pbs-post-install.XXXXXX) || return 1
    for tag in "v${REL_LATEST}" "${REL_LATEST}"; do
        url="https://raw.githubusercontent.com/${GH_REPO}/${tag}/pbs-post-install.sh"
        if http_get "$url" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then got=1; break; fi
    done
    if [ "$got" -ne 1 ]; then
        ulog "${RED}✘ The download failed - nothing was changed.${NC}"
        rm -f "$tmp"; return 1
    fi
    # --- check the file before it is allowed anywhere near the system ---
    fver=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$tmp" | head -n 1)
    if [ "$(stat -c %s "$tmp")" -lt 50000 ] || [ "$(head -c 11 "$tmp")" != '#!/bin/bash' ] \
        || ! bash -n "$tmp" 2>/dev/null || ! grep -q -- '--motd-update' "$tmp"; then
        ulog "${RED}✘ The downloaded file does not look right (syntax or size check failed) - nothing was changed.${NC}"
        rm -f "$tmp"; return 1
    fi
    if [ "$fver" != "$REL_LATEST" ]; then
        ulog "${RED}✘ The file says v${fver:-?} but the release is v${REL_LATEST} - nothing was changed.${NC}"
        mkdir -p "$BACKUP_DIR"; echo "$REL_LATEST" > "$BACKUP_DIR/skip"
        rm -f "$tmp"; return 1
    fi
    ulog "${GREEN}✔${NC} Downloaded v${fver} and checked it"
    # --- save the current version ---
    mkdir -p "$BACKUP_DIR"
    [ -f "$inst/pbs-motd" ] && cp -p "$inst/pbs-motd" "$BACKUP_DIR/pbs-motd.$old"
    [ -f "$inst/pbs-post-install.sh" ] && cp -p "$inst/pbs-post-install.sh" "$BACKUP_DIR/pbs-post-install.sh.$old"
    [ -f "$CONF" ] && cp -p "$CONF" "$BACKUP_DIR/pbs-motd.conf.$old"
    ulog "${GREEN}✔${NC} Saved v${old} in ${BACKUP_DIR}"
    # --- install, then try it; on any failure put the old files back ---
    if bash "$tmp" --motd-update >/dev/null 2>&1 \
        && [ "$("$inst/pbs-motd" --version 2>/dev/null)" = "pbs-motd v${fver}" ] \
        && bash -n "$inst/pbs-motd" 2>/dev/null && bash -n "$inst/pbs-post-install.sh" 2>/dev/null \
        && NO_COLOR=1 timeout 90 "$inst/pbs-motd" >/dev/null 2>&1; then
        rm -f "$BACKUP_DIR/skip"
        prune_backups
        UPDATED=1
        ulog "${GREEN}✔ Updated to v${fver}.${NC} It is active at the next login (or now: pbs-motd)."
    else
        restore_version "$old"
        echo "$REL_LATEST" > "$BACKUP_DIR/skip"
        ulog "${RED}✘ v${fver} did not pass the test - v${old} has been put back.${NC}"
        ulog "${DIM}This version will not be tried again automatically. Log: ${UPD_LOG}${NC}"
        rm -f "$tmp"; return 1
    fi
    rm -f "$tmp"
    return 0
}

do_rollback() {
    local f v
    need_root || return 1
    # shellcheck disable=SC2012
    f=$(ls -1t "$BACKUP_DIR"/pbs-motd.[0-9]* 2>/dev/null | head -n 1)
    if [ -z "$f" ]; then
        echo "  ${YELLOW}No earlier version is saved.${NC}"
        return 1
    fi
    v=${f##*/pbs-motd.}
    echo
    ask_yn "Go back to v${v} (the version before the last update)?" || return 0
    restore_version "$v"
    mkdir -p "$BACKUP_DIR"; echo "${PBS_MOTD_VERSION:-}" > "$BACKUP_DIR/skip"
    ulog "${GREEN}✔ Back on v${v}.${NC} The newer version will not be offered again until a newer one appears."
}

# Daily job: read the newest tag; install it when AUTO_UPDATE=1
run_check_release() {
    [ "$UPDATE_CHECK" = "1" ] || return 0
    check_release || true
    load_release
    if [ "$AUTO_UPDATE" = "1" ] && [ "$REL_NEW" -eq 1 ]; then
        installer_update auto
    fi
    return 0
}

# ---------------------------------------------------------------- traffic to the NAS
# The live views sample /sys/block/<disk>/stat every refresh and keep the last 20 values.
declare -A IO_PREV IO_RH IO_WH IO_LR IO_LW
IO_LIVE=0
IO_POINTS=20

mount_disk() {   # mount_disk /mnt/path -> disk name (sdb)
    local src dd
    src=$(findmnt -rn -M "$1" -o SOURCE 2>/dev/null)
    [ -n "$src" ] || return 1
    dd=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n 1)
    [ -n "$dd" ] || dd=$(basename "$src")
    echo "$dd"
}

sample_io() {
    local s MOUNT_PATH dd a c d e g h cs pcs pa pc pd pe pg ph dt rr wr dio lr lw prev
    cs=$(cut -d' ' -f1 /proc/uptime)
    cs=$(( 10#${cs/./} ))
    IO_LIVE=1
    while read -r -u 3 s; do
        [ -z "$s" ] && continue
        MOUNT_PATH=""
        # shellcheck disable=SC1090
        source <(grep -E '^MOUNT_PATH=' "$s")
        dd=$(mount_disk "$MOUNT_PATH") || continue
        [ -r "/sys/block/${dd}/stat" ] || continue
        read -r a _ c d e _ g h _ < "/sys/block/${dd}/stat"
        prev="${IO_PREV[$dd]:-}"
        IO_PREV[$dd]="$cs $a $c $d $e $g $h"
        [ -n "$prev" ] || continue
        read -r pcs pa pc pd pe pg ph <<< "$prev"
        dt=$(( cs - pcs ))
        [ "$dt" -ge 1 ] || continue
        rr=$(( (c - pc) * 512 * 100 / dt ))
        wr=$(( (g - pg) * 512 * 100 / dt ))
        dio=$(( a - pa )); lr=0
        [ "$dio" -gt 0 ] && lr=$(( (d - pd) / dio ))
        dio=$(( e - pe )); lw=0
        [ "$dio" -gt 0 ] && lw=$(( (h - ph) / dio ))
        [ "$rr" -lt 0 ] && rr=0
        [ "$wr" -lt 0 ] && wr=0
        # shellcheck disable=SC2086
        { set -- ${IO_RH[$dd]:-} "$rr"; while [ $# -gt "$IO_POINTS" ]; do shift; done; IO_RH[$dd]="$*"; }
        # shellcheck disable=SC2086
        { set -- ${IO_WH[$dd]:-} "$wr"; while [ $# -gt "$IO_POINTS" ]; do shift; done; IO_WH[$dd]="$*"; }
        IO_LR[$dd]="$lr"; IO_LW[$dd]="$lw"
    done 3< <(mon_scripts)
}

spark() {   # spark MAX v1 v2 ... -> · ░ ▒ ▓ █   (only characters every terminal font has)
    local max="$1" v i out=""
    local -a blocks=(· ░ ▒ ▓ █)
    shift
    [ "$max" -lt 1 ] && max=1
    for v in "$@"; do
        if [ "$v" -le 0 ]; then i=0; else i=$(( 1 + v * 3 / max )); fi
        [ "$i" -gt 4 ] && i=4
        out+="${blocks[i]}"
    done
    printf '%s' "$out"
}

rate_fmt() {
    awk -v b="${1:-0}" 'BEGIN {
        if (b >= 1073741824) printf "%.1f GB/s", b / 1073741824
        else if (b >= 1048576) printf "%.1f MB/s", b / 1048576
        else if (b >= 1024) printf "%.0f KB/s", b / 1024
        else printf "%d B/s", b }'
}

lat_colour() {   # milliseconds per request
    if [ "$1" -ge 1000 ]; then printf '%s' "$RED"
    elif [ "$1" -ge 200 ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi
}

panel_io() {
    local dd="$1" rh wh max v rn wn rpk=0 wpk=0 lr lw
    rh="${IO_RH[$dd]:-}"; wh="${IO_WH[$dd]:-}"
    if [ -z "$rh" ]; then
        kv "Traffic" "${DIM}measuring…${NC}"
        return 0
    fi
    max=1048576    # a flat line below 1 MB/s, so an idle disk looks idle
    # shellcheck disable=SC2086
    for v in $rh; do [ "$v" -gt "$max" ] && max=$v; [ "$v" -gt "$rpk" ] && rpk=$v; done
    # shellcheck disable=SC2086
    for v in $wh; do [ "$v" -gt "$max" ] && max=$v; [ "$v" -gt "$wpk" ] && wpk=$v; done
    rn=${rh##* }; wn=${wh##* }
    lr="${IO_LR[$dd]:-0}"; lw="${IO_LW[$dd]:-0}"
    # shellcheck disable=SC2086
    kv "Reads" "${CYAN}$(spark "$max" $rh)${NC} ${WHITE}$(rate_fmt "$rn")${NC}  ${DIM}peak $(rate_fmt "$rpk")${NC}"
    # shellcheck disable=SC2086
    kv "Writes" "${CYAN}$(spark "$max" $wh)${NC} ${WHITE}$(rate_fmt "$wn")${NC}  ${DIM}peak $(rate_fmt "$wpk")${NC}"
    kv "Latency" "read $(lat_colour "$lr")${lr} ms${NC} · write $(lat_colour "$lw")${lw} ms${NC}  ${DIM}average per request, last refresh${NC}"
}

panel_server() {
    local os kernel up load ncpu mt ma mpct rsz rused rpct d h m
    # shellcheck disable=SC1091
    os=$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}" )
    kernel=$(uname -r)
    up=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
    d=$(( up / 86400 )); h=$(( up % 86400 / 3600 )); m=$(( up % 3600 / 60 ))
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    ncpu=$(nproc 2>/dev/null || echo 1)
    mt=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    ma=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    mpct=0
    [ "${mt:-0}" -gt 0 ] && mpct=$(( (mt - ma) * 100 / mt ))
    read -r rsz rused < <(timeout 3 df -B1 --output=size,used / 2>/dev/null | tail -n 1)
    rpct=0
    [ "${rsz:-0}" -gt 0 ] && rpct=$(( rused * 100 / rsz ))

    panel_top "Server"
    kv "System" "${os} ${DIM}· kernel ${kernel}${NC}"
    kv "Uptime" "$( [ "$d" -gt 0 ] && echo "${d}d " )${h}h ${m}m   ${DIM}load ${load}  (${ncpu} cores)${NC}"
    kv "Memory" "$(bar "$mpct")  ${DIM}$(hb $(( (mt - ma) * 1024 ))) of $(hb $(( mt * 1024 )))${NC}"
    kv "System disk" "$(bar "$rpct")  ${DIM}$(hb "${rused:-0}") of $(hb "${rsz:-0}")${NC}"
    load_updates
    reboot_info
    if [ -n "$UPD_N" ]; then
        if [ "$UPD_N" -eq 0 ]; then
            st_good "Updates" "up to date ${DIM}(checked $(age $(( $(date +%s) - ${UPD_STAMP:-0} ))))${NC}"
        else
            kv "Updates" "${ALERT} ⚠ ${UPD_N} UPDATE(S) AVAILABLE ${NC}  ${DIM}$(trunc "$UPD_NAMES" $(( COLS - 44 )))${NC}"
            if [ "$UPD_IMP" = "1" ]; then
                kv "" "${RED}Kernel or core update - a reboot is needed afterwards${NC}"
            fi
            kv "" "${DIM}Install: press u at login, or pbs-menu › System updates${NC}"
        fi
    fi
    if [ "$REBOOT_NEEDED" -eq 1 ]; then
        kv "Reboot" "${ALERT} ⚠ REBOOT RECOMMENDED ${NC}  ${DIM}running ${RUNNING_K}, installed ${INSTALLED_K}${NC}"
        WARNINGS=$(( WARNINGS + 1 ))
    fi
    load_release
    if [ "$REL_NEW" -eq 1 ]; then
        kv "Installer" "${ALERT} ⚠ NEW VERSION v${REL_LATEST} ${NC}  ${DIM}you have v${PBS_MOTD_VERSION:-?}${NC}"
        kv "" "${DIM}Install: press i at login, or pbs-menu › Installer update${NC}"
    elif [ "$REL_SKIPPED" -eq 1 ]; then
        kv "Installer" "v${PBS_MOTD_VERSION:-?} ${DIM}· v${REL_LATEST} exists but was rolled back here - not offered again${NC}"
    elif [ "$UPDATE_CHECK" = "1" ] && [ "$REL_OK" -gt 0 ]; then
        st_good "Installer" "v${PBS_MOTD_VERSION:-?} ${DIM}· newest version (checked $(age $(( $(date +%s) - REL_OK ))))${NC}"
    fi
    panel_bottom
}

panel_iscsi() {
    local script="$1" TARGET="" PORTAL="" MOUNT_PATH="" STATE_FILE=""
    local state sid rt src fstype opts size used avail pct dev dsize tmo
    local auth_file last events cutoff ago disc dd
    # shellcheck disable=SC1090
    source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH|STATE_FILE)=' "$script" 2>/dev/null)
    [ -z "$TARGET" ] || [ -z "$MOUNT_PATH" ] && return 0
    echo
    panel_top "iSCSI storage · ${MOUNT_PATH}"
    st_info "Synology" "${PORTAL%%:*}   ${DIM}${TARGET##*:}${NC}"

    # --- session ---
    state=$(awk -v t="$TARGET" '/^[[:space:]]*Target:/ { in_t = ($2 == t) } in_t && /iSCSI Session State:/ { print $NF; exit }' <<< "$SESS3")
    sid=$(awk -v t="$TARGET" '$4 == t { gsub(/\[|\]/, "", $2); print $2; exit }' <<< "$SESS1")
    auth_file="${STATE_FILE}.authfail"
    if [ -n "$sid" ]; then
        if [ -z "$state" ] || [ "$state" = "LOGGED_IN" ]; then
            tmo=$(cat "/sys/class/iscsi_session/session${sid}/recovery_tmo" 2>/dev/null)
            st_good "Connection" "connected${tmo:+ ${DIM}· waits $(( tmo / 60 )) min for the NAS${NC}}"
        else
            st_bad "Connection" "${state} - the link is down or recovering"
        fi
    elif [ -f "$auth_file" ]; then
        st_bad "Connection" "not connected - the Synology REJECTED the CHAP login   ${DIM}pbs-post-install.sh --fix-login${NC}"
    else
        st_down "Connection" "not connected"
    fi

    # --- mount ---
    src=$(findmnt -rn -M "$MOUNT_PATH" -o SOURCE 2>/dev/null)
    if [ -z "$src" ]; then
        st_down "Mount" "not mounted"
    else
        fstype=$(findmnt -rn -M "$MOUNT_PATH" -o FSTYPE 2>/dev/null)
        opts=$(findmnt -rn -M "$MOUNT_PATH" -o OPTIONS 2>/dev/null)
        dsize=$(timeout 3 lsblk -bdno SIZE "$src" 2>/dev/null | head -n 1)
        dev="${src}${dsize:+ · $(hb "$dsize")} · ${fstype}"
        case ",${opts}," in
            *,ro,*) st_bad "Mount" "READ-ONLY - ${dev} hit an I/O error" ;;
            *)      st_good "Mount" "${dev} · read-write" ;;
        esac
        read -r size used avail < <(timeout 3 df -B1 --output=size,used,avail "$MOUNT_PATH" 2>/dev/null | tail -n 1)
        case "${size:-x}" in
            ''|*[!0-9]*) st_warn "Space" "df did not answer - the storage may be hanging" ;;
            *)
                pct=0
                [ "$size" -gt 0 ] && pct=$(( used * 100 / size ))
                kv "Space" "$(bar "$pct" 30)"
                kv "" "${WHITE}$(hb "$avail")${NC} free  ${DIM}· $(hb "$used") used of $(hb "$size")${NC}"
                if [ "$pct" -ge 95 ]; then
                    st_bad "" "almost full - backups will fail"
                elif [ "$pct" -ge 85 ]; then
                    st_warn "" "getting full - check prune and garbage collection"
                fi
                ;;
        esac
        # TRIM
        dd=$(basename "$(lsblk -no PKNAME "$src" 2>/dev/null | head -n 1)")
        [ -z "$dd" ] || [ "$dd" = "." ] && dd=$(basename "$src")
        disc=$(cat "/sys/block/${dd}/queue/discard_max_bytes" 2>/dev/null || echo 0)
        case "$(lun_provisioning "$dd")" in
            thin)
                if timeout 5 systemctl is-active --quiet fstrim.timer 2>/dev/null; then
                    st_info "LUN type" "thin ${DIM}· weekly TRIM gives deleted backups back to the Synology${NC}"
                else
                    st_warn "LUN type" "thin, but fstrim.timer is not running"
                fi
                ;;
            thin-off) st_warn "LUN type" "thin, but space reclamation is OFF on the Synology" ;;
            thick)    st_info "LUN type" "thick ${DIM}· space is reserved on the NAS, TRIM not needed${NC}" ;;
            *)
                if [ "${disc:-0}" -gt 0 ] 2>/dev/null; then
                    st_info "LUN type" "${DIM}not reported · accepts TRIM${NC}"
                else
                    st_info "LUN type" "${DIM}not reported${NC}"
                fi
                ;;
        esac
        if [ "$IO_LIVE" = "1" ]; then panel_io "$dd"; fi
    fi

    # --- monitor ---
    if crontab -l 2>/dev/null | grep -qF "$script"; then
        ago=""
        if [ -f "$STATE_FILE" ]; then
            ago=" ${DIM}· last check $(age $(( $(date +%s) - $(stat -c %Y "$STATE_FILE") )))${NC}"
        fi
        st_good "Monitor" "checks every minute, repairs by itself${ago}"
    else
        st_bad "Monitor" "the cron job is missing"
    fi
    cutoff=$(date -d '24 hours ago' '+%F %T')
    events=0
    if [ -r "$MON_LOG" ]; then
        events=$(awk -v c="$cutoff" 'substr($0, 1, 19) >= c' "$MON_LOG" \
            | grep -cE 'Failed|failed|Repairing|read-only|no answer|state is|REJECTED' || true)
        last=$(tail -n 1 "$MON_LOG" 2>/dev/null)
    fi
    if [ "${events:-0}" -gt 0 ]; then
        st_warn "Last 24 hours" "${events} problem event(s)   ${DIM}pbs-menu › Monitor log${NC}"
        [ -n "$last" ] && kv "Last log line" "${DIM}$(trunc "$last" $(( COLS - 22 )))${NC}"
    else
        st_good "Last 24 hours" "no problems logged"
    fi
    panel_bottom
}

# Name | path of every datastore
list_datastores() {
    awk '
        /^datastore:/ { name = $2 }
        $1 == "path" && name != "" { print name "|" $2; name = "" }
    ' "$DS_CFG" 2>/dev/null
}

panel_datastore() {
    local line name path n=0 types
    local -a ds=()
    mapfile -t ds < <(list_datastores)
    echo
    panel_top "Backups"
    if [ "${#ds[@]}" -eq 0 ]; then
        kv "Datastore" "${DIM}none yet${NC}"
    else
        for line in "${ds[@]}"; do
            name="${line%%|*}"; path="${line#*|}"
            kv "Datastore" "${WHITE}${name}${NC}  ${DIM}${path}${NC}"
        done
    fi
    # services
    local p1 p2
    p1=$(timeout 5 systemctl is-active proxmox-backup 2>/dev/null)
    p2=$(timeout 5 systemctl is-active proxmox-backup-proxy 2>/dev/null)
    if [ "$p1" = "active" ] && [ "$p2" = "active" ]; then
        st_good "PBS services" "running ${DIM}· web UI https://${IP:-<server-ip>}:8007${NC}"
    else
        st_bad "PBS services" "not running (api: ${p1:-?}, proxy: ${p2:-?})   ${DIM}pbs-menu › Services${NC}"
    fi
    # running tasks
    if [ -r "$TASK_DIR/active" ]; then
        n=$(grep -c '^UPID:' "$TASK_DIR/active" 2>/dev/null || true)
        if [ "${n:-0}" -gt 0 ]; then
            types=$(grep '^UPID:' "$TASK_DIR/active" | awk -F: '{print $7}' | sort | uniq -c | awk '{printf "%s%s×%s", (NR>1?", ":""), $1, $2}')
            st_info "Running now" "${CYAN}${n} task(s)${NC} ${DIM}${types}${NC}"
        fi
    fi
    # last finished tasks (best effort: format "UPID:...:type:id:user: ENDTIME-HEX STATUS")
    if [ -r "$TASK_DIR/archive" ]; then
        local cat hex status end now col
        now=$(date +%s)
        while IFS='|' read -r cat hex status; do
            [ -z "$cat" ] && continue
            case "$hex" in ''|*[!0-9A-Fa-f]*) continue ;; esac
            end=$(( 16#$hex ))
            case "$status" in
                OK*)       col="$GREEN" ;;
                WARNINGS*) col="$YELLOW" ;;
                *)         col="$RED" ;;
            esac
            kv "Last ${cat}" "${col}$(trunc "$status" 36)${NC} ${DIM}· $(age $(( now - end )))${NC}"
        done < <(tail -n 800 "$TASK_DIR/archive" 2>/dev/null | awk '
            {
                n = split($1, a, ":"); t = a[7]; c = ""
                if (t == "backup") c = "backup"
                else if (t == "garbage_collection") c = "GC"
                else if (t ~ /^verif/) c = "verify"
                else if (t ~ /^prune/) c = "prune"
                else if (t ~ /^sync|^pull|^push/) c = "sync"
                if (c == "") next
                st = $3; for (i = 4; i <= NF; i++) st = st " " $i
                last[c] = c "|" $2 "|" st
            }
            END {
                split("backup,GC,verify,prune,sync", o, ",")
                for (i = 1; i <= 5; i++) if (o[i] in last) print last[o[i]]
            }')
    fi
    panel_bottom
}

panel_keys() {
    echo
    panel_top "Quick keys" "$CYAN"
    panel_line "${CYAN}pbs-menu${NC}  menu     ${CYAN}pbs-help${NC}  key commands     ${CYAN}pbs-motd --watch${NC}  live view"
    if [ -x "$INSTALLER" ]; then
        panel_line "${CYAN}pbs-post-install.sh --status${NC}  full health check     ${CYAN}--fix-login${NC}  CHAP login"
    fi
    panel_bottom
}

# ---------------------------------------------------------------- dashboard
banner() {
    local pill="$1" i host ver
    local -a art=(
        "██████╗ ██████╗ ███████╗"
        "██╔══██╗██╔══██╗██╔════╝"
        "██████╔╝██████╔╝███████╗"
        "██╔═══╝ ██╔══██╗╚════██║"
        "██║     ██████╔╝███████║"
        "╚═╝     ╚═════╝ ╚══════╝"
    )
    host=$(hostname -s 2>/dev/null || hostname)
    ver=$(dpkg-query -W -f='${Version}' proxmox-backup-server 2>/dev/null)
    local -a side=(
        ""
        "${WHITE}${host}${NC}  ${DIM}${IP}${NC}"
        "${CYAN}Proxmox Backup Server${NC}  ${DIM}${ver%%-*}${NC}"
        "${DIM}iSCSI storage on Synology${NC}"
        "$pill"
        "${DIM}pbs-motd v${PBS_MOTD_VERSION:-?} · by MorphyDK${NC}"
    )
    echo
    if [ "${SLIM:-0}" = "1" ]; then
        printf '  %s%s%s  %s%s%s  %s  %s\n' "$WHITE" "$host" "$NC" "$DIM" "$IP" "$NC" "$pill" "${DIM}v${PBS_MOTD_VERSION:-?}${NC}"
    elif [ "$COLS" -ge 76 ]; then
        for (( i = 0; i < 6; i++ )); do
            printf '   %s%s%s   %s\n' "${GRAD[i]}" "${art[i]}" "$NC" "${side[i]}"
        done
    else
        for (( i = 1; i < 6; i++ )); do
            printf '  %s\n' "${side[i]}"
        done
    fi
    printf '  %s%s%s\n' "$CYAN" "$(printf '━%.0s' $(seq 1 $(( COLS > 66 ? 64 : COLS - 4 ))))" "$NC"
}

render_dashboard() {
    local tmp pill scripts s
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    PROBLEMS=0; WARNINGS=0
    tmp=$(mktemp) || return 1
    gather_sessions
    {
        echo
        panel_server
        shopt -s nullglob
        scripts=(/usr/local/bin/check-iscsi-session-*.sh)
        shopt -u nullglob
        if [ "${#scripts[@]}" -eq 0 ]; then
            echo
            panel_top "iSCSI storage" "$YELLOW"
            panel_line "${YELLOW}No iSCSI installation found.${NC} Run pbs-post-install.sh to set one up."
            panel_bottom
        else
            for s in "${scripts[@]}"; do panel_iscsi "$s"; done
        fi
        panel_datastore
    } > "$tmp"
    if [ "$PROBLEMS" -gt 0 ]; then
        pill="${RED}✘ ${PROBLEMS} PROBLEM(S) - needs attention${NC}"
    elif [ "$WARNINGS" -gt 0 ]; then
        pill="${YELLOW}⚠ working, ${WARNINGS} warning(s)${NC}"
    else
        pill="${GREEN}● ALL SYSTEMS HEALTHY${NC}"
    fi
    banner "$pill"
    cat "$tmp"
    rm -f "$tmp"
}

# ---------------------------------------------------------------- help
render_help() {
    local mnt
    mnt=$(sed -n 's/^MOUNT_PATH=//p' /usr/local/bin/check-iscsi-session-*.sh 2>/dev/null | head -n 1 | tr -d "'\"\\\\")
    mnt="${mnt:-/mnt/pbs}"
    echo
    echo "  ${WHITE}Key commands${NC}  ${DIM}copy, paste, press Enter${NC}"
    echo
    panel_top "This login screen"
    kv "Menu" "pbs-menu"
    kv "Dashboard" "pbs-motd"
    kv "Live view" "pbs-motd --watch   ${DIM}(refreshes every 3 seconds, q quits)${NC}"
    kv "This page" "pbs-help"
    panel_bottom
    echo
    panel_top "Connection to the Synology"
    kv "Session" "iscsiadm -m session -P 1"
    kv "Health check" "pbs-post-install.sh --status"
    kv "CHAP login" "pbs-post-install.sh --fix-login"
    kv "Monitor log" "tail -f /var/log/iscsi-monitor.log"
    kv "Kernel log" "journalctl -u iscsid -n 50"
    panel_bottom
    echo
    panel_top "Storage"
    kv "Space" "df -h ${mnt}"
    kv "Mount" "findmnt ${mnt}"
    kv "Disks" "lsblk -f"
    kv "TRIM" "fstrim -v ${mnt}"
    panel_bottom
    echo
    panel_top "Proxmox Backup Server"
    kv "Datastores" "proxmox-backup-manager datastore list"
    kv "Tasks" "proxmox-backup-manager task list"
    kv "Services" "systemctl status proxmox-backup-proxy"
    kv "Logs" "journalctl -u proxmox-backup-proxy -n 50"
    kv "Versions" "proxmox-backup-manager versions"
    kv "Update" "apt update && apt full-upgrade"
    panel_bottom
    echo
    echo "  ${DIM}Web UI: https://$(hostname -I 2>/dev/null | awk '{print $1}'):8007${NC}"
    echo
}

# ---------------------------------------------------------------- input
KEY=""
read_key() {
    local k="" rest=""
    IFS= read -rsn1 k || true
    if [ "$k" = $'\e' ]; then
        IFS= read -rsn2 -t 0.05 rest || true
        k+="$rest"
    fi
    case "$k" in
        $'\e[A'|$'\eOA'|k|K) KEY="up" ;;
        $'\e[B'|$'\eOB'|j|J) KEY="down" ;;
        "")                  KEY="enter" ;;
        q|Q|$'\e')           KEY="quit" ;;
        [0-9])               KEY="num$k" ;;
        *)                   KEY="other" ;;
    esac
}

press_key() {
    printf '\n  %sPress any key to go back…%s' "$DIM" "$NC"
    IFS= read -rsn1 _ || true
}

ask_yn() {   # ask_yn "Question"  -> 0 = yes (default no)
    local k
    printf '\n  %s %s[y/N]%s ' "$1" "$DIM" "$NC"
    IFS= read -rsn1 k || true
    echo
    [ "$k" = "y" ] || [ "$k" = "Y" ]
}

# menu_select VAR default "Label|hint" ...  ->  index, or -1 when q / Esc
menu_select() {
    local __var="$1" sel="$2" item n i first=1 d
    shift 2
    local -a labels=() hints=()
    for item in "$@"; do
        labels+=("${item%%|*}")
        case "$item" in *"|"*) hints+=("${item#*|}") ;; *) hints+=("") ;; esac
    done
    n=${#labels[@]}
    echo
    printf '  %s↑/↓ choose · Enter select · 1-9 jump · q back%s\n' "$DIM" "$NC"
    printf '\e[?25l'
    while true; do
        [ "$first" -eq 0 ] && printf '\e[%dA' $(( n + 1 ))
        first=0
        for (( i = 0; i < n; i++ )); do
            if [ "$i" -eq "$sel" ]; then
                printf '\r\e[K  %s❯ %d%s  %s%s%s\n' "$CYAN" $(( i + 1 )) "$NC" "$WHITE" "${labels[i]}" "$NC"
            else
                printf '\r\e[K    %s%d%s  %s\n' "$DIM" $(( i + 1 )) "$NC" "${labels[i]}"
            fi
        done
        printf '\r\e[K       %s%s%s\n' "$DIM" "$(trunc "${hints[sel]}" $(( COLS - 9 )))" "$NC"
        read_key
        case "$KEY" in
            up)    sel=$(( (sel - 1 + n) % n )) ;;
            down)  sel=$(( (sel + 1) % n )) ;;
            enter) break ;;
            quit)  sel=-1; break ;;
            num*)  d=${KEY#num}
                   if [ "$d" -ge 1 ] && [ "$d" -le "$n" ]; then sel=$(( d - 1 )); fi ;;
        esac
    done
    printf '\e[?25h'
    printf -v "$__var" '%s' "$sel"
}

# ---------------------------------------------------------------- screens
need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "  ${YELLOW}This needs root - run:  sudo $0${NC}" >&2
        return 1
    fi
}

mon_scripts() {
    local f
    for f in /usr/local/bin/check-iscsi-session-*.sh; do
        [ -f "$f" ] && echo "$f"
    done
}

screen_watch() {
    local out k
    frame_close
    printf '\e[?25l\e[2J'
    trap 'printf "\e[?25h"; exit 0' INT TERM
    while true; do
        sample_io
        out=$(render_dashboard 2>&1)
        # shellcheck disable=SC2001
        printf '\e[H%s\n' "$(sed 's/$/\x1b[K/' <<< "$out")"
        printf '\n  %sLive view · refreshes every 3 seconds · %s · q to quit%s\e[K\n\e[J' "$DIM" "$(date '+%H:%M:%S')" "$NC"
        k=""
        IFS= read -rsn1 -t 3 k
        case "$k" in q|Q|$'\e') break ;; esac
    done
    printf '\e[?25h\n'
    trap - INT TERM
}

screen_lun() {
    local s TARGET PORTAL MOUNT_PATH iqn rt st auth user sid line
    iqn=$(awk -F= '/^InitiatorName=/ {print $2}' /etc/iscsi/initiatorname.iscsi 2>/dev/null)
    gather_sessions
    while read -r -u 3 s; do
        [ -z "$s" ] && continue
        TARGET=""; PORTAL=""; MOUNT_PATH=""
        # shellcheck disable=SC1090
        source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH)=' "$s")
        echo
        panel_top "Drive details · ${MOUNT_PATH}"
        kv "Target" "${TARGET}"
        kv "Synology" "${PORTAL}"
        kv "This server" "${iqn:-unknown}"
        rt=$(iscsiadm -m node -T "$TARGET" -p "$PORTAL" 2>/dev/null | awk -F' = ' '$1=="node.session.timeo.replacement_timeout"{print $2}')
        st=$(iscsiadm -m node -T "$TARGET" -p "$PORTAL" 2>/dev/null | awk -F' = ' '$1=="node.startup"{print $2}')
        auth=$(iscsiadm -m node -T "$TARGET" -p "$PORTAL" 2>/dev/null | awk -F' = ' '$1=="node.session.auth.authmethod"{print $2}')
        user=$(iscsiadm -m node -T "$TARGET" -p "$PORTAL" 2>/dev/null | awk -F' = ' '$1=="node.session.auth.username"{print $2}')
        kv "Login" "${auth:-none}${user:+ · user ${user}} ${DIM}(password hidden)${NC}"
        kv "Starts at boot" "${st:-?}"
        kv "Reconnect wait" "${rt:-?} s"
        sid=$(awk -v t="$TARGET" '$4 == t { gsub(/\[|\]/, "", $2); print $2; exit }' <<< "$SESS1")
        if [ -n "$sid" ]; then kv "Session" "id ${sid}"; else kv "Session" "${RED}none${NC}"; fi
        panel_bottom
        echo
        panel_top "Session details (iscsiadm)"
        timeout 10 iscsiadm -m session -P 1 2>/dev/null | awk -v t="$TARGET" '
            /^Target:/ { in_t = ($2 == t) }
            in_t && NF { print }' | while IFS= read -r line; do panel_line "${DIM}${line}${NC}"; done
        panel_bottom
    done 3< <(mon_scripts)
    echo
    panel_top "Disks"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,TRAN 2>/dev/null | while IFS= read -r line; do panel_line "$line"; done
    panel_bottom
}

screen_drives() {   # the Drives submenu: details, add, CHAP login, remove
    local c n
    need_root || return 0
    while true; do
        clear_body
        n=$(mon_scripts | wc -l)
        echo
        panel_top "Drives"
        panel_line "${n} drive(s) set up on this server. ${DIM}Remove never erases data on the Synology.${NC}"
        panel_bottom
        menu_select c 0 \
            "Drive details|Target, login, session details and disks of every drive (read-only)" \
            "Add a drive|Connect another Synology LUN and create or re-attach its datastore" \
            "Change the CHAP login|Type the username/password again (Synology log: CHAP required but absent)" \
            "Remove a drive|Disconnect a LUN from this server and remove its datastore from PBS" \
            "Back"
        case "$c" in
            0) page_run screen_lun; press_key ;;
            1) drive_tool --add-drive; return 0 ;;
            2) drive_tool --fix-login; return 0 ;;
            3) drive_tool --remove-drive; return 0 ;;
            *) return 0 ;;
        esac
    done
}

drive_tool() {   # runs the installer full-screen (it draws its own screens), then the menu comes back
    term_reset
    printf '\e[2J\e[H'
    if [ -x "$INSTALLER" ]; then
        "$INSTALLER" "$1" || true
    else
        echo "  ${YELLOW}The installer copy (${INSTALLER}) was not found - run: pbs-motd --update-installer${NC}"
    fi
    press_key
}

screen_storage() {
    local s MOUNT_PATH line
    echo
    panel_top "Space"
    while read -r -u 3 s; do
        [ -z "$s" ] && continue
        MOUNT_PATH=""
        # shellcheck disable=SC1090
        source <(grep -E '^MOUNT_PATH=' "$s")
        timeout 5 df -hT "$MOUNT_PATH" 2>/dev/null | while IFS= read -r line; do panel_line "$line"; done
    done 3< <(mon_scripts)
    panel_bottom
    echo
    panel_top "Datastores (proxmox-backup-manager)"
    timeout 15 proxmox-backup-manager datastore list 2>/dev/null | while IFS= read -r line; do panel_line "$line"; done
    panel_bottom
    echo
    panel_top "Open tasks"
    timeout 15 proxmox-backup-manager task list 2>/dev/null | head -n 12 | while IFS= read -r line; do panel_line "$(trunc "$line" $(( COLS - 6 )))"; done
    panel_bottom
}

screen_health() {
    if [ -x "$INSTALLER" ]; then
        if command -v script >/dev/null 2>&1; then
            # a pseudo terminal, so the colours survive when the output is captured for paging
            script -qec "$INSTALLER --status" /dev/null | tr -d '\r'
        else
            "$INSTALLER" --status
        fi
    else
        echo "  ${YELLOW}The installer copy (${INSTALLER}) was not found, so the full health check is not available.${NC}"
        echo "  ${DIM}Run the installer again, or use the dashboard.${NC}"
    fi
}

screen_repair() {
    local s STATE_FILE
    echo
    panel_top "Check & repair now"
    panel_line "Runs the monitor once, right now. If the connection or mount is broken it"
    panel_line "repairs it: unmount › logout › login › mount › restart PBS."
    panel_line "${DIM}A healthy system is left alone. Nothing is formatted or erased.${NC}"
    panel_bottom
    ask_yn "Run the monitor now?" || return 0
    echo
    while read -r -u 3 s; do
        [ -z "$s" ] && continue
        STATE_FILE=""
        # shellcheck disable=SC1090
        source <(grep -E '^STATE_FILE=' "$s")
        rm -f "${STATE_FILE}.repair" "${STATE_FILE}.authfail"
        echo "  ${CYAN}►${NC} $(basename "$s")"
        timeout 400 "$s" </dev/null
    done 3< <(mon_scripts)
    echo
    echo "  ${GREEN}Done.${NC} ${DIM}Last lines of the monitor log:${NC}"
    screen_log 8
}

screen_log() {
    local n="${1:-30}" line
    [ -r "$MON_LOG" ] || { echo "  ${DIM}No monitor log yet - nothing has gone wrong.${NC}"; return 0; }
    echo
    panel_top "Monitor log · last ${n} lines"
    tail -n "$n" "$MON_LOG" | while IFS= read -r line; do
        case "$line" in
            *REJECTED*|*Failed*|*failed*|*read-only*|*"no answer"*) panel_line "${RED}$(trunc "$line" $(( COLS - 6 )))${NC}" ;;
            *Success*|*succeeded*|*healthy*)                      panel_line "${GREEN}$(trunc "$line" $(( COLS - 6 )))${NC}" ;;
            *)                                                    panel_line "${DIM}$(trunc "$line" $(( COLS - 6 )))${NC}" ;;
        esac
    done
    panel_bottom
}

screen_services() {
    local u st c
    while true; do
        clear_body
        echo
        panel_top "Services"
        for u in proxmox-backup proxmox-backup-proxy iscsid cron fstrim.timer; do
            st=$(timeout 5 systemctl is-active "$u" 2>/dev/null)
            case "$st" in active) c="$GREEN" ;; *) c="$RED" ;; esac
            kv "$u" "${c}${st:-unknown}${NC}"
        done
        panel_bottom
        menu_select c 0 \
            "Restart the PBS services|Restarts proxmox-backup and proxmox-backup-proxy - running backups are interrupted" \
            "Back"
        case "$c" in
            0)
                if ask_yn "Restart the PBS services now? Running backups will stop."; then
                    timeout 90 systemctl restart proxmox-backup proxmox-backup-proxy \
                        && echo "  ${GREEN}✔ Restarted${NC}" || echo "  ${RED}✘ Restart failed - see journalctl -u proxmox-backup-proxy${NC}"
                    sleep 2
                fi
                ;;
            *) return 0 ;;
        esac
    done
}

running_tasks() {
    local n
    n=$(grep -c '^UPID:' "$TASK_DIR/active" 2>/dev/null)
    echo "${n:-0}"
}

do_reboot() {
    local n
    n=$(running_tasks)
    echo
    if [ "$n" -gt 0 ]; then
        echo "  ${RED}⚠ ${n} backup task(s) are running - a reboot will interrupt them.${NC}"
    fi
    if ask_yn "Reboot the server now?"; then
        echo "  ${CYAN}Rebooting…${NC}"
        systemctl reboot
        sleep 5
    fi
}

# Check, show and (after a yes) install the available updates
do_update() {
    local raw n tasks line
    need_root || return 1
    echo
    printf '  %sChecking for updates…%s' "$DIM" "$NC"
    if ! timeout 180 apt-get -q update >/dev/null 2>&1; then
        printf '\r\e[K'
        echo "  ${YELLOW}⚠ apt update reported problems (a repository may be unreachable).${NC}"
        echo "  ${DIM}Run apt update to see the details.${NC}"
    else
        printf '\r\e[K'
    fi
    refresh_updates
    load_updates
    if [ -z "$UPD_N" ] || [ "$UPD_N" -eq 0 ]; then
        echo "  ${GREEN}✔ The system is up to date.${NC}"
        return 0
    fi
    raw=$(timeout 30 apt-get -s dist-upgrade 2>/dev/null | awk '/^Inst /{print $2 " " $3 " -> " $4}' | tr -d '[]()')
    echo
    panel_top "${UPD_N} update(s) available" "$YELLOW"
    n=0
    while IFS= read -r line; do
        n=$(( n + 1 ))
        [ "$n" -gt 15 ] && { panel_line "${DIM}… and $(( UPD_N - 15 )) more${NC}"; break; }
        panel_line "$(trunc "$line" $(( COLS - 6 )))"
    done <<< "$raw"
    panel_bottom
    if [ "$UPD_IMP" = "1" ]; then
        echo
        panel_top "Kernel or core update" "$RED"
        panel_line "${ALERT} ⚠ A REBOOT IS NEEDED AFTERWARDS ${NC}"
        panel_line "The new kernel only runs after a reboot. Plan it for a quiet moment."
        panel_bottom
    fi
    tasks=$(running_tasks)
    if [ "$tasks" -gt 0 ]; then
        echo "  ${RED}⚠ ${tasks} backup task(s) are running - the PBS services restart during an upgrade and may interrupt them.${NC}"
    fi
    ask_yn "Install the ${UPD_N} update(s) now?" || { echo "  ${DIM}Nothing was installed.${NC}"; return 0; }
    echo
    if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none \
        apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade; then
        echo
        echo "  ${GREEN}✔ Updates installed.${NC}"
    else
        echo
        echo "  ${RED}✘ The upgrade reported errors - see the output above.${NC}"
    fi
    refresh_updates
    load_updates
    reboot_info
    if [ "$REBOOT_NEEDED" -eq 1 ] || [ "$UPD_IMP" = "1" ]; then
        echo
        panel_top "Reboot" "$RED"
        panel_line "${ALERT} ⚠ REBOOT STRONGLY RECOMMENDED ${NC}"
        panel_line "Running kernel ${RUNNING_K}, installed ${INSTALLED_K}."
        panel_line "${DIM}The iSCSI disk reconnects by itself after the reboot.${NC}"
        panel_bottom
        do_reboot
    fi
    return 0
}

snoozed() {
    local until
    until=$(cat "$SNOOZE_FILE" 2>/dev/null || echo 0)
    [ "$(date +%s)" -lt "${until:-0}" ]
}

save_conf() {
    need_root || return 0
    printf 'MODE=%s\nPROMPT_SECS=%s\nUPDATE_PROMPT=%s\nUPDATE_CHECK=%s\nAUTO_UPDATE=%s\nREFRESH_SECS=%s\n' \
        "$MODE" "$PROMPT_SECS" "$UPDATE_PROMPT" "$UPDATE_CHECK" "$AUTO_UPDATE" "$REFRESH_SECS" > "$CONF"
    chmod 644 "$CONF"
}

screen_settings() {
    local c cur
    need_root || return 0
    while true; do
        clear_body
        echo
        panel_top "Settings"
        kv "Login screen" "${MODE}$( [ "$MODE" = "live" ] && echo " ${DIM}(stays open until q)${NC}" )"
        kv "Update question" "$( [ "$UPDATE_PROMPT" = "1" ] && echo 'on - asks at login when updates are available' || echo 'off - the dashboard only shows them' )"
        kv "Installer check" "$( [ "$UPDATE_CHECK" = "1" ] && echo 'on - looks once a day on GitHub for a newer version' || echo 'off - never contacts GitHub' )"
        kv "Auto-install" "$( [ "$AUTO_UPDATE" = "1" ] && echo "${YELLOW}on - installs a newer installer by itself${NC}" || echo 'off - you decide (press i)' )"
        kv "Live refresh" "every ${REFRESH_SECS} seconds"
        panel_blank
        panel_line "${DIM}Applies from the next login.${NC}"
        panel_bottom
        menu_select c 0 \
            "Change the login screen|Dashboard only, dashboard + menu prompt, live dashboard, or off" \
            "Turn the update question $( [ "$UPDATE_PROMPT" = "1" ] && echo off || echo on )|At login: offer to install available updates (u = install, s = snooze 24 h)" \
            "Turn the installer check $( [ "$UPDATE_CHECK" = "1" ] && echo off || echo on )|One request a day to api.github.com to see if a newer version exists" \
            "Turn auto-install $( [ "$AUTO_UPDATE" = "1" ] && echo off || echo on )|A newer installer is installed without asking (checked, saved and rolled back if it fails)" \
            "Live refresh: ${REFRESH_SECS}s|Change how often the live dashboard redraws (2, 3, 5 or 10 seconds)" \
            "Back"
        case "$c" in
            0)
                cur=1
                case "$MODE" in off) cur=3 ;; dashboard) cur=0 ;; live) cur=2 ;; esac
                menu_select c "$cur" \
                    "Dashboard only|Shows the dashboard at login, then your shell" \
                    "Dashboard + menu prompt|After the dashboard: press m for the menu, h for help (${PROMPT_SECS}s, then the shell)" \
                    "Live dashboard|Stays open and refreshes until you press q - with a key bar for menu, log, repair and updates" \
                    "Off|No login screen - pbs-menu still works"
                case "$c" in
                    0) MODE=dashboard ;;
                    1) MODE=prompt ;;
                    2) MODE=live ;;
                    3) MODE=off ;;
                esac
                save_conf
                ;;
            1) if [ "$UPDATE_PROMPT" = "1" ]; then UPDATE_PROMPT=0; else UPDATE_PROMPT=1; fi; save_conf ;;
            2) if [ "$UPDATE_CHECK" = "1" ]; then UPDATE_CHECK=0; else UPDATE_CHECK=1; fi; save_conf ;;
            3) if [ "$AUTO_UPDATE" = "1" ]; then AUTO_UPDATE=0; else
                   AUTO_UPDATE=1; UPDATE_CHECK=1
               fi
               save_conf ;;
            4) menu_select c 1 "2 seconds|Fast, a little more load" "3 seconds|Default" "5 seconds|Calmer" "10 seconds|Very calm"
               case "$c" in 0) REFRESH_SECS=2 ;; 1) REFRESH_SECS=3 ;; 2) REFRESH_SECS=5 ;; 3) REFRESH_SECS=10 ;; esac
               save_conf ;;
            *) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------- frozen header + drive cards (menus)
# In the menus the logo and the status pill stay at the top; the menu and every screen scroll in
# the part below (a terminal scroll region). On a small terminal a slim 3-line header is used.
FRAME=0; HDR_H=0
term_reset() { printf '\e[r\e[?25h'; }

DRV_NAME=(); DRV_STATE=(); DRV_FS=(); DRV_PCT=(); DRV_AVAIL=(); DRV_SIZE=(); DRV_PROV=()
MENU_PROB=0; MENU_PILL=""; SVC_OK=1
menu_collect() {   # the state of every drive + services: feeds the header pill, the cards and the badges
    local s TARGET MOUNT_PATH src up fs size used avail pct dd opts prov ro i=0
    DRV_NAME=(); DRV_STATE=(); DRV_FS=(); DRV_PCT=(); DRV_AVAIL=(); DRV_SIZE=(); DRV_PROV=()
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    MENU_PROB=0; SVC_OK=1
    gather_sessions
    while read -r -u 3 s; do
        [ -z "$s" ] && continue
        TARGET=""; MOUNT_PATH=""
        # shellcheck disable=SC1090
        source <(grep -E '^(TARGET|MOUNT_PATH)=' "$s")
        up=0
        grep -qF "$TARGET" <<< "$SESS1" && up=1
        src=$(findmnt -rn -M "$MOUNT_PATH" -o SOURCE 2>/dev/null)
        fs=""; pct=0; avail=0; size=0; used=0; prov=""; ro=0
        if [ -n "$src" ]; then
            fs=$(findmnt -rn -M "$MOUNT_PATH" -o FSTYPE 2>/dev/null)
            opts=$(findmnt -rn -M "$MOUNT_PATH" -o OPTIONS 2>/dev/null)
            case ",${opts}," in *,ro,*) ro=1 ;; esac
            read -r size used avail < <(timeout 3 df -B1 --output=size,used,avail "$MOUNT_PATH" 2>/dev/null | tail -n 1)
            case "${size:-x}" in ''|*[!0-9]*) size=0; used=0; avail=0 ;; esac
            [ "$size" -gt 0 ] && pct=$(( used * 100 / size ))
            if dd=$(mount_disk "$MOUNT_PATH"); then prov=$(lun_provisioning "$dd"); fi
        fi
        DRV_NAME[i]=$(basename "$MOUNT_PATH")
        if [ "$up" -eq 0 ] || [ -z "$src" ]; then
            DRV_STATE[i]=0; MENU_PROB=$(( MENU_PROB + 1 ))
        elif [ "$ro" -eq 1 ]; then
            DRV_STATE[i]=2; MENU_PROB=$(( MENU_PROB + 1 ))
        else
            DRV_STATE[i]=1
        fi
        DRV_FS[i]="$fs"; DRV_PCT[i]="$pct"; DRV_AVAIL[i]="$avail"; DRV_SIZE[i]="$size"; DRV_PROV[i]="$prov"
        i=$(( i + 1 ))
    done 3< <(mon_scripts)
    if ! timeout 5 systemctl is-active --quiet proxmox-backup-proxy 2>/dev/null; then
        SVC_OK=0; MENU_PROB=$(( MENU_PROB + 1 ))
    fi
    if [ "$MENU_PROB" -gt 0 ]; then
        MENU_PILL="${RED}✘ ${MENU_PROB} PROBLEM(S) - needs attention${NC}"
    else
        MENU_PILL="${GREEN}● ALL SYSTEMS HEALTHY${NC}"
    fi
    load_updates; reboot_info; load_release
    return 0
}

frame_open() {   # collect, draw the header at the top, keep it there
    local hdr rows
    rows=$(tput lines 2>/dev/null || echo 24)
    case "$rows" in ''|*[!0-9]*) rows=24 ;; esac
    COLS=$(term_cols)
    menu_collect
    if [ "$rows" -lt 16 ]; then          # too small for a frozen header: plain screens
        FRAME=0; HDR_H=0
        printf '\e[r\e[2J\e[H'
        return 0
    fi
    SLIM=0
    [ "$rows" -lt 34 ] && SLIM=1
    hdr=$(banner "$MENU_PILL")
    HDR_H=$(wc -l <<< "$hdr")
    printf '\e[r\e[?25l\e[H\e[J%s\n' "$hdr"
    printf '\e[%d;%dr\e[%d;1H\e[?25h' $(( HDR_H + 1 )) "$rows" $(( HDR_H + 1 ))
    FRAME=1
}

clear_body() {   # clear everything below the frozen header (or the whole screen when there is none)
    if [ "$FRAME" -eq 1 ]; then
        printf '\e[%d;1H\e[J' $(( HDR_H + 1 ))
    else
        printf '\e[2J\e[H'
    fi
}

frame_close() {
    if [ "$FRAME" -eq 1 ]; then printf '\e[r'; fi
    FRAME=0
}

# A screen that is taller than the space below the frozen header is shown page by page
# (lines that scroll off the top of a scroll region are gone, so nothing may scroll off).
page_file() {   # page_file FILE
    local f="$1" total per rows k rest i=0 end
    rows=$(tput lines 2>/dev/null || echo 24)
    case "$rows" in ''|*[!0-9]*) rows=24 ;; esac
    per=$(( rows - HDR_H - 4 ))
    [ "$per" -lt 6 ] && per=6
    total=$(wc -l < "$f")
    if [ "$total" -le "$per" ]; then
        cat "$f"
        return 0
    fi
    printf '\e[?25l'
    while true; do
        clear_body
        end=$(( i + per ))
        [ "$end" -gt "$total" ] && end=$total
        [ $(( total - end )) -le 2 ] && end=$total        # no page of one or two stray lines
        sed -n "$(( i + 1 )),${end}p" "$f"
        printf '\n  %s── lines %d-%d of %d · space/↓ next · b/↑ back · q done ──%s' "$DIM" $(( i + 1 )) "$end" "$total" "$NC"
        IFS= read -rsn1 k || break
        if [ "$k" = $'\e' ]; then
            rest=""
            IFS= read -rsn2 -t 0.05 rest || true
            case "$rest" in
                '[B'|'OB') k=" " ;;
                '[A'|'OA') k="b" ;;
                '[6')      k=" "; IFS= read -rsn1 -t 0.05 _ || true ;;
                '[5')      k="b"; IFS= read -rsn1 -t 0.05 _ || true ;;
                *)         k="q" ;;
            esac
        fi
        case "$k" in
            q|Q) break ;;
            b|B|k) i=$(( i - per )); [ "$i" -lt 0 ] && i=0 ;;
            *)  if [ "$end" -ge "$total" ]; then break; fi      # space / Enter / n / j: next page, past the end = done
                i=$(( i + per )) ;;
        esac
    done
    printf '\r\e[K\e[?25h\n'
}

page_run() {   # page_run COMMAND [ARGS] - run it, show the output (paged when it is long)
    local tmp
    tmp=$(mktemp) || { "$@"; return 0; }
    printf '  %sCollecting…%s' "$DIM" "$NC"
    "$@" > "$tmp" 2>&1
    printf '\r\e[K'
    page_file "$tmp"
    rm -f "$tmp"
}

menu_cards() {   # one small drive icon + status per LUN
    local i n=${#DRV_NAME[@]} col status info prov
    if [ "$n" -eq 0 ]; then
        echo "  ${YELLOW}No iSCSI drive set up yet.${NC} ${DIM}Run pbs-post-install.sh${NC}"
        return 0
    fi
    for (( i = 0; i < n; i++ )); do
        case "${DRV_STATE[i]}" in
            1) col="$GREEN"; status="${GREEN}● connected${NC}" ;;
            2) col="$RED";   status="${RED}● READ-ONLY${NC}" ;;
            *) col="$RED";   status="${RED}● not connected${NC}" ;;
        esac
        case "${DRV_PROV[i]}" in thin|thin-off) prov="thin" ;; thick) prov="thick" ;; *) prov="" ;; esac
        info="${DRV_FS[i]:-no filesystem mounted}"
        [ -n "$prov" ] && info="${prov} · ${info}"
        [ "${DRV_SIZE[i]}" -gt 0 ] && info="${info} · $(hb "${DRV_SIZE[i]}")"
        printf '  %s▄▄▄%s  %s%s%s  %s%s%s   %s\n' "$WHITE" "$NC" "$WHITE" "${DRV_NAME[i]}" "$NC" "$DIM" "$info" "$NC" "$status"
        if [ "${DRV_STATE[i]}" -eq 0 ]; then
            printf '  %s█%s●%s█%s  %swaiting for the NAS - the monitor reconnects by itself%s\n' "$WHITE" "$col" "$WHITE" "$NC" "$DIM" "$NC"
        else
            printf '  %s█%s●%s█%s  %s  %s%s%s free\n' "$WHITE" "$col" "$WHITE" "$NC" "$(bar "${DRV_PCT[i]}" 28)" "$WHITE" "$(hb "${DRV_AVAIL[i]}")" "$NC"
        fi
    done
}

# menu_grid: four groups (rows) of three items. Arrows move, Enter chooses, a number or letter is a
# shortcut, q / Esc leaves. Result: the item number 0-11 in GRID_SEL.
GRID_SEL=0
menu_grid() {
    local sel="$1" r c i w k rest rc cols_w0=0 cols_w1=0 cols_w2=0 gl gap=2 cell txt pad
    local -a keys=(1 2 3 4 5 6 7 8 9 0 s q)
    local -a labels=("Live view" "Drives" "Storage" "Health check" "Check & repair" "Monitor log" \
                     "Services" "System updates" "Installer" "Help" "Settings" "Back to shell")
    local -a hints=(
        "The dashboard, refreshing every ${REFRESH_SECS} seconds"
        "Drive details, add a drive, CHAP login, remove a drive"
        "Free space, datastores, open tasks"
        "Full check including a test write (pbs-post-install.sh --status)"
        "Runs the monitor once - repairs a lost connection"
        "The last events from the iSCSI monitor"
        "Status of PBS, iSCSI and cron - restart PBS"
        "Check for updates and install them - advises a reboot after kernel updates"
        "Newer version of this installer / login screen on GitHub"
        "The commands you will need"
        "Login style, update question, installer check, auto-install"
        "Leave the menu"
    )
    local -a badge=() bcol=() groups=("WATCH" "CHECK" "SYSTEM" "OTHER")
    for (( i = 0; i < 12; i++ )); do badge[i]=""; bcol[i]=""; done
    if [ "${MENU_PROB:-0}" -gt 0 ]; then badge[1]="[!]"; bcol[1]="$RED"; badge[4]="[!]"; bcol[4]="$RED"; fi
    if [ "$SVC_OK" -eq 0 ]; then badge[6]="[!]"; bcol[6]="$RED"; fi
    if [ "${UPD_N:-0}" -gt 0 ]; then badge[7]="[${UPD_N}]"; bcol[7]="$ALERT"
    elif [ "$REBOOT_NEEDED" -eq 1 ]; then badge[7]="[reboot]"; bcol[7]="$ALERT"; fi
    if [ "$REL_NEW" -eq 1 ]; then badge[8]="[NEW]"; bcol[8]="$ALERT"; hints[8]="v${REL_LATEST} is available - install it here"; fi

    # column widths from the widest cell (label + badge), so the arrows line up
    for (( i = 0; i < 12; i++ )); do
        w=$(( ${#keys[i]} + 1 + ${#labels[i]} + ${#badge[i]} + ( ${#badge[i]} > 0 ? 1 : 0 ) + 2 ))
        case $(( i % 3 )) in
            0) [ "$w" -gt "$cols_w0" ] && cols_w0=$w ;;
            1) [ "$w" -gt "$cols_w1" ] && cols_w1=$w ;;
            2) [ "$w" -gt "$cols_w2" ] && cols_w2=$w ;;
        esac
    done
    gl=9
    [ $(( gl + cols_w0 + cols_w1 + cols_w2 + 3 * gap + 2 )) -gt "$COLS" ] && gl=0

    echo
    printf '  %s←↑↓→ move · Enter choose · or press the number / letter · q leaves%s\n' "$DIM" "$NC"
    printf '\e[?25l'
    local first=1
    while true; do
        [ "$first" -eq 0 ] && printf '\e[6A'
        first=0
        for (( r = 0; r < 4; r++ )); do
            printf '\r\e[K  '
            [ "$gl" -gt 0 ] && printf '%s%-*s%s' "$DIM" "$gl" "${groups[r]}" "$NC"
            for (( c = 0; c < 3; c++ )); do
                i=$(( r * 3 + c ))
                txt="${keys[i]} ${labels[i]}"
                [ -n "${badge[i]}" ] && txt="${txt} ${badge[i]}"
                case "$c" in 0) w=$cols_w0 ;; 1) w=$cols_w1 ;; *) w=$cols_w2 ;; esac
                pad=$(( w - ${#txt} - 2 ))
                if [ "$i" -eq "$sel" ]; then
                    printf '\e[1;97;44m %s%*s \e[0m' "$txt" "$pad" ""
                else
                    cell=" ${CYAN}${keys[i]}${NC} ${labels[i]}"
                    [ -n "${badge[i]}" ] && cell="${cell} ${bcol[i]}${badge[i]}${NC}"
                    printf '%s%*s ' "$cell" "$pad" ""
                fi
                printf '%*s' "$gap" ""
            done
            printf '\n'
        done
        printf '\r\e[K\n\r\e[K  %s%s%s\n' "$DIM" "$(trunc "${hints[sel]}" $(( COLS - 4 )))" "$NC"
        k=""
        IFS= read -rsn1 k
        rc=$?
        [ "$rc" -ne 0 ] && { sel=11; break; }
        if [ "$k" = $'\e' ]; then
            rest=""
            IFS= read -rsn2 -t 0.05 rest || true
            case "$rest" in
                '[A'|'OA') sel=$(( (sel + 9) % 12 )) ;;
                '[B'|'OB') sel=$(( (sel + 3) % 12 )) ;;
                '[C'|'OC') sel=$(( sel / 3 * 3 + (sel % 3 + 1) % 3 )) ;;
                '[D'|'OD') sel=$(( sel / 3 * 3 + (sel % 3 + 2) % 3 )) ;;
                '')        sel=11; break ;;
            esac
            continue
        fi
        if [ -z "$k" ]; then break; fi                       # Enter
        for (( i = 0; i < 12; i++ )); do
            if [ "${k,,}" = "${keys[i]}" ]; then sel=$i; break 2; fi
        done
    done
    printf '\e[?25h'
    GRID_SEL=$sel
}

menu_main() {
    local c=0
    need_root || exit 1
    trap term_reset EXIT
    trap 'term_reset; exit 0' INT TERM
    while true; do
        frame_open
        menu_cards
        menu_grid "$c"
        c=$GRID_SEL
        clear_body
        case "$c" in
            0) screen_watch; continue ;;
            1) screen_drives; continue ;;
            2) page_run screen_storage ;;
            3) page_run screen_health ;;
            4) screen_repair ;;
            5) page_run screen_log 40 ;;
            6) screen_services; continue ;;
            7) do_update ;;
            8) installer_update
               if [ "$UPDATED" -eq 1 ]; then press_key; exec /usr/local/sbin/pbs-motd --menu; fi ;;
            9) page_run render_help ;;
            10) screen_settings; continue ;;
            *) break ;;
        esac
        press_key
    done
    frame_close
    printf '\e[2J\e[H'
    trap - INT TERM
}

# A small terminal (the Proxmox console is 80x25) cannot show everything at once. The panels are
# split over pages instead of cutting the picture off: n / space / → = next page, b / ← = back.
PAGE=0; PAGES=1
PAGE_OUT=""
paginate() {   # paginate "TEXT" MAXLINES -> sets PAGE_OUT (the page to draw) and PAGES; keeps PAGE in range
    local text="$1" maxl="$2" i p L cur=0 avail np=0 hdr_end=-1
    local -a lines=() pfirst=() plast=() pg_first=() pg_last=() sel=()
    mapfile -t lines <<< "$text"
    for (( i = 0; i < ${#lines[@]}; i++ )); do
        case "${lines[i]}" in
            *"╭─"*) pfirst[np]=$(( i > 0 ? i - 1 : 0 ))
                    [ "$hdr_end" -lt 0 ] && hdr_end=${pfirst[np]} ;;
            *"╰─"*) plast[np]=$i; np=$(( np + 1 )) ;;
        esac
    done
    if [ "$np" -eq 0 ] || [ "$hdr_end" -lt 0 ]; then
        PAGES=1; PAGE=0
        printf -v PAGE_OUT '%s\n' "${lines[@]:0:maxl}"
        return 0
    fi
    avail=$(( maxl - hdr_end ))
    [ "$avail" -lt 6 ] && avail=6
    PAGES=0
    for (( p = 0; p < np; p++ )); do
        L=$(( plast[p] - pfirst[p] + 1 ))
        if [ "$cur" -gt 0 ] && [ $(( cur + L )) -gt "$avail" ]; then
            pg_last[PAGES]=$(( p - 1 )); PAGES=$(( PAGES + 1 )); cur=0
        fi
        [ "$cur" -eq 0 ] && pg_first[PAGES]=$p
        cur=$(( cur + L ))
    done
    pg_last[PAGES]=$(( np - 1 )); PAGES=$(( PAGES + 1 ))
    [ "$PAGE" -ge "$PAGES" ] && PAGE=0
    [ "$PAGE" -lt 0 ] && PAGE=$(( PAGES - 1 ))
    sel=("${lines[@]:0:hdr_end}")
    for (( p = pg_first[PAGE]; p <= pg_last[PAGE]; p++ )); do
        sel+=("${lines[@]:pfirst[p]:plast[p]-pfirst[p]+1}")
    done
    printf -v PAGE_OUT '%s\n' "${sel[@]:0:maxl}"
}

# ---------------------------------------------------------------- live dashboard (login style "live")
# The dashboard stays on screen and refreshes until you press q. A key bar at the bottom shows
# what you can do; alerts (updates, reboot, new installer) appear there in sharp red.
cockpit() {
    local out k rc rest n rows maxl bar hint alerts last_rows=0
    if ! [ -t 0 ] || ! [ -t 1 ]; then
        render_dashboard; return 0
    fi
    SLIM=0
    trap term_reset EXIT
    trap 'term_reset; printf "\n"; exit 0' INT TERM
    printf '\e[?25l\e[2J'
    while true; do
        COLS=$(term_cols)
        rows=$(tput lines 2>/dev/null || echo 24)
        case "$rows" in ''|*[!0-9]*) rows=24 ;; esac
        [ "$rows" != "$last_rows" ] && { SLIM=0; last_rows=$rows; printf '\e[2J'; }
        # the state that decides the key bar (the dashboard itself is drawn in a subshell)
        load_updates; reboot_info; load_release
        sample_io
        alerts=""
        [ "${UPD_N:-0}" -gt 0 ] && alerts="${alerts} ${ALERT} u ${NC} ${WHITE}update (${UPD_N})${NC}  "
        [ "$REL_NEW" -eq 1 ] && alerts="${alerts} ${ALERT} i ${NC} ${WHITE}installer v${REL_LATEST}${NC}  "
        [ "$REBOOT_NEEDED" -eq 1 ] && alerts="${alerts} ${ALERT} r ${NC} ${WHITE}reboot${NC}"
        maxl=$(( rows - 3 ))
        [ -n "$alerts" ] && maxl=$(( maxl - 1 ))
        out=$(render_dashboard 2>&1)
        n=$(wc -l <<< "$out")
        if [ "$n" -gt "$maxl" ] && [ "$SLIM" -eq 0 ]; then
            SLIM=1
            out=$(render_dashboard 2>&1)
            n=$(wc -l <<< "$out")
        fi
        if [ "$n" -gt "$maxl" ]; then
            paginate "$out" "$maxl"
            out=${PAGE_OUT%$'\n'}
        else
            PAGES=1; PAGE=0
        fi
        bar=" ${CYAN}m${NC} menu  ${CYAN}l${NC} log  ${CYAN}c${NC} repair  ${CYAN}h${NC} help"
        [ "$PAGES" -gt 1 ] && bar="${bar}  ${CYAN}n${NC} page"
        bar="${bar}  ${CYAN}p${NC} all  ${CYAN}q${NC} shell"
        [ -n "$alerts" ] && bar="${alerts}"$'\e[K\n'"${bar}"
        hint="${DIM}live · every ${REFRESH_SECS}s · $(date '+%H:%M:%S')"
        [ "$PAGES" -gt 1 ] && hint="${hint} · page $(( PAGE + 1 ))/${PAGES}"
        # shellcheck disable=SC2001
        printf '\e[H%s\n' "$(sed 's/$/\x1b[K/' <<< "$out")"
        printf '\e[K\n%s\e[K\n  %s%s\e[K\e[J' "$bar" "$hint" "$NC"
        k=""
        IFS= read -rsn1 -t "$REFRESH_SECS" k
        rc=$?
        [ "$rc" -gt 128 ] && continue           # timeout: just redraw
        if [ "$k" = $'\e' ]; then
            rest=""
            IFS= read -rsn2 -t 0.05 rest || true
            case "$rest" in
                '[C'|'OC') k="n" ;;            # → next page
                '[D'|'OD') k="b" ;;            # ← previous page
                '')        ;;                  # a bare Esc leaves
                *)         k="arrow" ;;        # other escape sequences are ignored
            esac
        fi
        case "$k" in
            q|Q|$'\e'|"") break ;;               # q, Esc or Enter: back to the shell
            n|N|" "|$'\t') [ "$PAGES" -gt 1 ] && PAGE=$(( (PAGE + 1) % PAGES )); printf '\e[2J' ;;
            b|B) [ "$PAGES" -gt 1 ] && PAGE=$(( (PAGE + PAGES - 1) % PAGES )); printf '\e[2J' ;;
            m|M) printf '\e[?25h\e[2J\e[H'; menu_main; printf '\e[?25l\e[2J' ;;
            l|L) printf '\e[?25h\e[2J\e[H'; screen_log 40; press_key; printf '\e[?25l\e[2J' ;;
            c|C) printf '\e[?25h\e[2J\e[H'; screen_repair; press_key; printf '\e[?25l\e[2J' ;;
            h|H) printf '\e[?25h\e[2J\e[H'; render_help; press_key; printf '\e[?25l\e[2J' ;;
            p|P) printf '\e[?25h\e[2J\e[H'; SLIM=0 render_dashboard 2>&1 | less -R; printf '\e[?25l\e[2J' ;;
            u|U) if [ "${UPD_N:-0}" -gt 0 ]; then
                     printf '\e[?25h\e[2J\e[H'; do_update; press_key; printf '\e[?25l\e[2J'
                 fi ;;
            i|I) if [ "$REL_NEW" -eq 1 ]; then
                     printf '\e[?25h\e[2J\e[H'
                     installer_update
                     press_key
                     [ "$UPDATED" -eq 1 ] && exec /usr/local/sbin/pbs-motd --live
                     printf '\e[?25l\e[2J'
                 fi ;;
            r|R) if [ "$REBOOT_NEEDED" -eq 1 ]; then
                     printf '\e[?25h\e[2J\e[H'; do_reboot; press_key; printf '\e[?25l\e[2J'
                 fi ;;
        esac
    done
    printf '\e[?25h\n'
    echo "  ${DIM}Live dashboard closed.  pbs-motd --live  opens it again · pbs-menu  menu${NC}"
    echo
    trap - INT TERM EXIT
}

# ---------------------------------------------------------------- login
# Right after a boot the iSCSI link is not up yet. Wait for it (max 25 s) instead of
# showing red lines. After 6 s the monitor is started once, the same thing cron does every
# minute (it never runs twice at once and only repairs what is broken).
wait_for_storage() {
    local s i=0 ready kicked=0 sp="|/-\\" TARGET MOUNT_PATH sess shown=0
    [ "$(uptime_secs)" -ge 600 ] && return 0
    [ "$(id -u)" -eq 0 ] || return 0
    while [ "$i" -lt 25 ]; do
        ready=1
        sess=$(timeout 5 iscsiadm -m session 2>/dev/null)
        while read -r -u 3 s; do
            [ -z "$s" ] && continue
            TARGET=""; MOUNT_PATH=""
            # shellcheck disable=SC1090
            source <(grep -E '^(TARGET|MOUNT_PATH)=' "$s")
            if ! grep -qF "$TARGET" <<< "$sess" || ! findmnt -rn -M "$MOUNT_PATH" >/dev/null 2>&1; then
                ready=0
            fi
        done 3< <(mon_scripts)
        [ "$ready" -eq 1 ] && break
        shown=1
        printf '\r  %s%s Waiting for the Synology connection - the server just started…%s\e[K' "$CYAN" "${sp:$(( i % 4 )):1}" "$NC"
        if [ "$i" -eq 6 ] && [ "$kicked" -eq 0 ]; then
            kicked=1
            while read -r -u 3 s; do
                [ -z "$s" ] && continue
                ( timeout 90 "$s" </dev/null >/dev/null 2>&1 & )
            done 3< <(mon_scripts)
        fi
        sleep 1
        i=$(( i + 1 ))
    done
    [ "$shown" -eq 1 ] && printf '\r\e[K'
    return 0
}

do_login() {
    local k want_upd=0 want_rel=0 secs parts is_root=0
    [ "$MODE" = "off" ] && return 0
    [ "$(id -u)" -eq 0 ] && is_root=1
    wait_for_storage
    if [ "$MODE" = "live" ] && [ "$is_root" -eq 1 ] && [ -t 0 ] && [ -t 1 ]; then
        cockpit
        return 0
    fi
    render_dashboard
    panel_keys
    echo
    if [ "$is_root" -eq 1 ] && [ "$UPDATE_PROMPT" = "1" ] && ! snoozed; then
        [ "${UPD_N:-0}" -gt 0 ] && want_upd=1
        [ "$REL_NEW" -eq 1 ] && want_rel=1
    fi
    if [ "$MODE" = "prompt" ] || [ "$want_upd" -eq 1 ] || [ "$want_rel" -eq 1 ] \
        || { [ "$REBOOT_NEEDED" -eq 1 ] && [ "$is_root" -eq 1 ]; }; then
        secs="$PROMPT_SECS"
        parts=""
        if [ "$want_upd" -eq 1 ]; then
            parts="${parts}${ALERT} u ${NC} ${WHITE}install the ${UPD_N} update(s)${NC}   "
        fi
        if [ "$want_rel" -eq 1 ]; then
            parts="${parts}${ALERT} i ${NC} ${WHITE}installer v${REL_LATEST}${NC}   "
        fi
        if [ "$REBOOT_NEEDED" -eq 1 ] && [ "$is_root" -eq 1 ]; then
            parts="${parts}${ALERT} r ${NC} ${WHITE}reboot${NC}   "
        fi
        if [ -n "$parts" ]; then
            [ "$secs" -lt 10 ] && secs=10
            [ "$want_upd" -eq 1 ] || [ "$want_rel" -eq 1 ] && parts="${parts}${CYAN}s${NC} ${DIM}snooze 24h${NC}"
            echo "  ${parts}"
        fi
        printf '  %sm%s %smenu ·%s %sh%s %shelp · or wait %ss%s ' "$CYAN" "$NC" "$DIM" "$NC" "$CYAN" "$NC" "$DIM" "$secs" "$NC"
        k=""
        IFS= read -rsn1 -t "$secs" k
        printf '\r\e[K'
        case "$k" in
            u|U) [ "$want_upd" -eq 1 ] && do_update ;;
            i|I) if [ "$want_rel" -eq 1 ]; then
                     installer_update
                     [ "$UPDATED" -eq 1 ] && exec /usr/local/sbin/pbs-motd --login
                 fi ;;
            s|S) if [ "$want_upd" -eq 1 ] || [ "$want_rel" -eq 1 ]; then
                     mkdir -p "$(dirname "$SNOOZE_FILE")"
                     echo $(( $(date +%s) + 86400 )) > "$SNOOZE_FILE"
                     echo "  ${DIM}No update question for 24 hours. The dashboard still shows them.${NC}"
                 fi ;;
            r|R) [ "$REBOOT_NEEDED" -eq 1 ] && [ "$is_root" -eq 1 ] && do_reboot ;;
            m|M) [ "$is_root" -eq 1 ] && menu_main ;;
            h|H) render_help ;;
        esac
    fi
}

case "$(basename "$0")" in
    pbs-menu) set -- --menu ;;
    pbs-help) set -- --help ;;
esac

case "${1:-}" in
    "")        render_dashboard; panel_keys; echo ;;
    --login)   do_login ;;
    --live)    need_root || exit 1; cockpit ;;
    --watch)   screen_watch ;;
    --check-release) run_check_release ;;
    --update-installer) installer_update ;;
    --rollback) do_rollback ;;
    --menu)    menu_main ;;
    --help|-h) render_help ;;
    --refresh-updates) refresh_updates ;;
    --version) echo "pbs-motd v${PBS_MOTD_VERSION:-?}" ;;
    *)         echo "Usage: pbs-motd [--login|--live|--watch|--menu|--help|--update-installer|--rollback]" >&2; exit 2 ;;
esac
exit 0
MOTD_EOF
    } > "${dest}.new" && mv -f "${dest}.new" "$dest"
}

# Copies this installer to /usr/local/sbin (so --status / --fix-login work from anywhere)
install_self_copy() {
    if [[ -f "$0" ]]; then
        # copy + rename: a copy of the installer that is running right now is never rewritten in place
        if [[ "$0" -ef /usr/local/sbin/pbs-post-install.sh ]] \
            || { cp "$0" /usr/local/sbin/pbs-post-install.sh.new 2>/dev/null \
                 && mv -f /usr/local/sbin/pbs-post-install.sh.new /usr/local/sbin/pbs-post-install.sh; }; then
            chmod 755 /usr/local/sbin/pbs-post-install.sh
            return 0
        fi
    fi
    [[ -x /usr/local/sbin/pbs-post-install.sh ]]
}

motd_conf_val() {   # motd_conf_val KEY -> value from /etc/pbs-motd.conf (empty when absent)
    sed -n "s/^$1=//p" /etc/pbs-motd.conf 2>/dev/null | head -n 1
}

install_motd_files() {
    mkdir -p /var/lib/pbs-motd
    write_motd_script /usr/local/sbin/pbs-motd
    chmod 755 /usr/local/sbin/pbs-motd
    ln -sf /usr/local/sbin/pbs-motd /usr/local/bin/pbs-menu
    ln -sf /usr/local/sbin/pbs-motd /usr/local/bin/pbs-help
    ln -sf /usr/local/sbin/pbs-motd /usr/local/bin/pbs-motd
    local mode="$MOTD_MODE" m up pr chk auto ref
    up=$(motd_conf_val UPDATE_PROMPT); pr=$(motd_conf_val PROMPT_SECS)
    chk=$(motd_conf_val UPDATE_CHECK); auto=$(motd_conf_val AUTO_UPDATE); ref=$(motd_conf_val REFRESH_SECS)
    if [[ ${MOTD_KEEP_CONF:-0} -eq 1 ]]; then
        m=$(motd_conf_val MODE)
        [[ -n "$m" ]] && mode="$m"
    fi
    printf 'MODE=%s\nPROMPT_SECS=%s\nUPDATE_PROMPT=%s\nUPDATE_CHECK=%s\nAUTO_UPDATE=%s\nREFRESH_SECS=%s\n' \
        "$mode" "${pr:-5}" "${up:-1}" "${chk:-1}" "${auto:-0}" "${ref:-3}" > /etc/pbs-motd.conf
    chmod 644 /etc/pbs-motd.conf
    # Refresh the "updates available" count right after apt update / dpkg runs
    cat > /etc/apt/apt.conf.d/99pbs-motd <<'APTHOOK_EOF'
// Written by pbs-post-install: keep the login screen's update count current
DPkg::Post-Invoke { "sh -c '(sleep 3; /usr/local/sbin/pbs-motd --refresh-updates) >/dev/null 2>&1 &'"; };
APT::Update::Post-Invoke-Success { "sh -c '(sleep 3; /usr/local/sbin/pbs-motd --refresh-updates) >/dev/null 2>&1 &'"; };
APTHOOK_EOF
    cat > /etc/profile.d/pbs-motd.sh <<'PROFILE_EOF'
# Login dashboard for Proxmox Backup Server (written by pbs-post-install).
# Remove with:  pbs-post-install.sh --motd-remove     Turn off: MODE=off in /etc/pbs-motd.conf
case "$-" in *i*) ;; *) return 0 2>/dev/null ;; esac
[ -t 0 ] && [ -t 1 ] || return 0
[ "$(id -u)" = "0" ] || return 0
[ -n "${PBS_MOTD_SHOWN:-}" ] && return 0
[ -x /usr/local/sbin/pbs-motd ] || return 0
export PBS_MOTD_SHOWN=1
/usr/local/sbin/pbs-motd --login
PROFILE_EOF
    chmod 644 /etc/profile.d/pbs-motd.sh
    # The static banner would show up twice - keep a copy of it
    if [[ -s /etc/motd ]]; then
        [[ -f /etc/motd.pbs-orig ]] || cp /etc/motd /etc/motd.pbs-orig
        : > /etc/motd
    fi
    # Daily count of pending updates (read by the dashboard; no network needed)
    cat > /etc/cron.d/pbs-motd <<'CRON_EOF'
# Written by pbs-post-install: refresh the "updates available" count for the login screen
17 6 * * * root /usr/local/sbin/pbs-motd --refresh-updates >/dev/null 2>&1
# Once a day: is there a newer version of this installer on GitHub? (Settings: installer check)
@@CHECK@@ 7 * * * root /usr/local/sbin/pbs-motd --check-release >/dev/null 2>&1
CRON_EOF
    sed -i "s/@@CHECK@@/$(( RANDOM % 50 + 5 ))/" /etc/cron.d/pbs-motd
    chmod 644 /etc/cron.d/pbs-motd
    /usr/local/sbin/pbs-motd --refresh-updates >/dev/null 2>&1 || true
}

step_motd() {
    if [[ $DO_MOTD -ne 1 ]]; then
        skip_step $S_MOTD "not requested"
        return 0
    fi
    begin_step $S_MOTD
    install_motd_files
    ok "Login dashboard installed: ${WHITE}/usr/local/sbin/pbs-motd${NC}"
    ok "Commands: ${WHITE}pbs-motd${NC} (dashboard) · ${WHITE}pbs-menu${NC} (menu) · ${WHITE}pbs-help${NC} (key commands)"
    if install_self_copy; then
        SELF_CMD="pbs-post-install.sh --status"
    fi
    finish_step $S_MOTD "$( case "$MOTD_MODE" in prompt) echo 'dashboard + menu prompt' ;; live) echo 'live dashboard' ;; *) echo 'dashboard' ;; esac ) at login"
}

# --motd : install or update only the login screen
run_motd_only() {
    if [[ $EUID -ne 0 ]]; then
        echo "--motd needs root. Run:  sudo $0 --motd" >&2
        return 2
    fi
    touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
    INSTALL_STARTED=1
    if [[ -t 0 && -t 1 ]]; then
        printf '\033[2J\033[H'
        render_banner
        DO_MOTD=1
        setup_motd
    else
        MOTD_KEEP_CONF=1
    fi
    install_motd_files
    install_self_copy || true
    echo
    ok "Login screen installed - it shows at the next login."
    echo "  ${DIM}Preview now: pbs-motd · menu: pbs-menu · help: pbs-help${NC}"
    echo
}

# --motd-update : silent update of the login screen + installer copy, keeps all settings.
# Used by "pbs-motd --update-installer" (the one-key update) and the optional auto-install.
run_motd_update() {
    if [[ $EUID -ne 0 ]]; then
        echo "--motd-update needs root." >&2
        return 2
    fi
    MOTD_KEEP_CONF=1
    install_motd_files
    install_self_copy
    echo "pbs-post-install v${VERSION}: login screen and installer updated."
}

run_motd_remove() {
    if [[ $EUID -ne 0 ]]; then
        echo "--motd-remove needs root. Run:  sudo $0 --motd-remove" >&2
        return 2
    fi
    rm -f /etc/profile.d/pbs-motd.sh /etc/cron.d/pbs-motd /etc/pbs-motd.conf /etc/apt/apt.conf.d/99pbs-motd \
          /usr/local/bin/pbs-menu /usr/local/bin/pbs-help /usr/local/bin/pbs-motd /usr/local/sbin/pbs-motd
    rm -rf /var/lib/pbs-motd
    rm -f /var/log/pbs-motd-update.log /var/lock/pbs-motd-update.lock
    if [[ -f /etc/motd.pbs-orig ]]; then
        mv /etc/motd.pbs-orig /etc/motd
    fi
    echo "  ${GREEN}✔${NC} Login screen removed (the original /etc/motd is back)."
}

step_datastore() {
    local -a args=()
    if [[ $DO_DS -ne 1 ]]; then
        skip_step $S_DS "not requested"
        return 0
    fi
    if [[ $DS_SKIP -eq 1 ]]; then
        skip_step $S_DS "'${DS_NAME}' already exists"
        return 0
    fi
    begin_step $S_DS
    if [[ $DO_ISCSI -eq 1 ]] && ! mountpoint -q "$MOUNT_PATH"; then
        fail_step $S_DS "${MOUNT_PATH} is not mounted - skipped to protect the local disk"
        return 0
    fi
    args=(datastore create "$DS_NAME" "$DS_PATH")
    if [[ $DS_REUSE -eq 1 ]]; then
        if ! reuse_supported; then
            fail_step $S_DS "re-attach in the web UI: Datastore › Add, tick 'reuse existing datastore'"
            return 0
        fi
        args+=(--reuse-datastore true)
    fi
    run_quiet_soft "Creating datastore '${DS_NAME}' (can take a minute)" proxmox-backup-manager "${args[@]}"
    if [[ $RUN_RC -eq 0 ]]; then
        if [[ $DS_REUSE -eq 1 ]]; then
            finish_step $S_DS "re-attached '${DS_NAME}' at ${DS_PATH}"
        else
            finish_step $S_DS "'${DS_NAME}' at ${DS_PATH}"
        fi
    else
        err "Datastore creation failed (exit code ${RUN_RC}). Last log lines:"
        tail -n 8 "$LOG_FILE" | sed 's/^/    /'
        fail_step $S_DS "failed - see ${LOG_FILE}"
    fi
}

step_nag() {
    local js="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    if [[ $DO_NAG -ne 1 ]]; then
        skip_step $S_NAG "not requested"
        return 0
    fi
    begin_step $S_NAG
    # The "NO NAG" method of the community-scripts post-pbs-install script (MIT):
    # an apt hook patches proxmoxlib.js after every package change.
    # Older versions of this installer used a different patch - remove it first
    rm -f /usr/local/bin/pbs-remove-nag.sh /etc/apt/apt.conf.d/99-pbs-no-nag
    if grep -q 'NO-NAG' "$js" 2>/dev/null; then
        run_quiet_soft "Restoring the original web interface file" \
            "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" --reinstall install proxmox-widget-toolkit
    fi
    cat > /etc/apt/apt.conf.d/no-nag-script <<'NAG_EOF'
DPkg::Post-Invoke { "if [ -s /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ] && ! grep -q -F 'NoMoreNagging' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then sed -i '/data\.status/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi" };
NAG_EOF
    ok "Apt hook installed: ${DIM}/etc/apt/apt.conf.d/no-nag-script (re-applied after every update)${NC}"
    # Reinstalling the package runs the hook right away
    run_quiet_soft "Applying the patch (reinstalling proxmox-widget-toolkit)" \
        "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" --reinstall install proxmox-widget-toolkit
    if grep -q 'NoMoreNagging' "$js" 2>/dev/null; then
        run_quiet_soft "Restarting the web interface" systemctl restart proxmox-backup-proxy
        note "Subscription popup removed - reload the web UI with Ctrl+Shift+R (Cmd+Shift+R on Mac)"
        finish_step $S_NAG "removed · kept after updates"
    else
        warn "The popup could not be removed - this PBS version's web UI code is different"
        skip_step $S_NAG "not possible on this version"
    fi
}

step_finish() {
    local failed=0 s fp el choice
    finish_step $S_FIN "all done"
    render_screen
    for s in "${STEP_STATUS[@]}"; do
        if [[ "$s" == "failed" ]]; then
            failed=1
        fi
    done
    mono
    el=$(( MONO - INSTALL_START ))
    if [[ $failed -eq 1 ]]; then
        echo "  ${YELLOW}⚠  Finished with problems - see the red step above and ${LOG_FILE}${NC}"
    else
        echo "  ${GREEN}✔  PBS post-install completed successfully in $(( el / 60 ))m $(( el % 60 ))s!${NC}"
    fi
    echo

    if [[ $DO_ISCSI -eq 1 ]]; then
        panel_top "iSCSI"
        kv "Target" "$TARGET_IQN"
        kv "Synology" "$PORTAL_IP"
        kv "Device" "$DEVICE_PATH  (${LUN_SIZE_H}, ${FS_TYPE})"
        kv "Mount path" "$MOUNT_PATH"
        kv "fstab" "${DIM}${FSTAB_ENTRY}${NC}"
        kv "Monitor" "${CHECK_ISCSI_SCRIPT} ${DIM}(log: /var/log/iscsi-monitor.log)${NC}"
        kv "Reconnect wait" "$(( REPLACEMENT_TIMEOUT / 60 )) minutes ${DIM}(open-iscsi default is 2)${NC}"
        if [[ "$DISK_ACTION" != "mounted" ]]; then
            panel_line "${DIM}The empty mount directory is immutable; to remove it later: chattr -i ${MOUNT_PATH}${NC}"
        fi
        panel_bottom
        echo
    fi

    if [[ ${#NOTES[@]} -gt 0 ]]; then
        panel_top "Notes" "$YELLOW"
        for s in "${NOTES[@]}"; do
            panel_line "• ${s}"
        done
        panel_bottom
        echo
    fi

    fp=$(proxmox-backup-manager cert info 2>/dev/null | grep -i 'fingerprint' | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' || true)
    panel_top "Next steps" "$GREEN"
    panel_line "1. Open the PBS web UI: ${WHITE}https://${HOST_IP:-<server-ip>}:8007${NC}"
    if [[ $DO_DS -eq 1 ]]; then
        panel_line "2. In Proxmox VE: Datacenter › Storage › Add › Proxmox Backup Server"
        panel_line "   Server ${WHITE}${HOST_IP:-<server-ip>}${NC} · Datastore ${WHITE}${DS_NAME}${NC}"
        if [[ -n "$fp" ]]; then
            panel_line "   Fingerprint ${DIM}${fp}${NC}"
        fi
        panel_line "3. Check the prune and garbage-collection schedule on the datastore"
    fi
    if [[ $DO_ISCSI -eq 1 ]]; then
        panel_line "Health check any time: ${WHITE}${SELF_CMD:-re-run the installer with --status}${NC}"
    fi
    if [[ $DO_MOTD -eq 1 ]]; then
        panel_line "Login screen: ${WHITE}pbs-motd${NC} shows it now · ${WHITE}pbs-menu${NC} opens the menu · ${WHITE}pbs-help${NC} lists key commands"
    fi
    panel_bottom
    echo "  ${DIM}Install log: ${LOG_FILE}${NC}"

    if [[ -f /var/run/reboot-required ]]; then
        NEED_REBOOT=1
    fi
    if [[ $NEED_REBOOT -eq 1 ]]; then
        menu_select choice 0 \
            "Reboot now (recommended)|Applies the upgraded kernel and packages" \
            "Reboot later|Remember to reboot soon"
        if [[ $choice -eq 0 ]]; then
            echo "  ${CYAN}Rebooting...${NC}"
            reboot
        else
            echo "  ${YELLOW}Reboot skipped - remember to reboot later.${NC}"
        fi
    fi
    echo
}

run_install() {
    PHASE="install"
    INSTALL_STARTED=1
    mono
    INSTALL_START=$MONO
    prune_other_nodes
    echo "=== Installation started $(date '+%F %T')" >> "$LOG_FILE"

    step_repos
    step_upgrade
    if [[ $DO_ISCSI -eq 1 ]]; then
        step_connect
        step_disk
        step_mount
        step_monitor
    else
        skip_step $S_CONN "iSCSI not selected"
        skip_step $S_DISK "iSCSI not selected"
        skip_step $S_MOUNT "iSCSI not selected"
        skip_step $S_MON "iSCSI not selected"
    fi
    step_datastore
    step_nag
    step_motd
    step_finish
}

# ===========================================================================
# STATUS DASHBOARD  (--status)  - read-only health check, changes nothing
# ===========================================================================
ST_PROBLEMS=0
ST_WARNINGS=0

st_info() { kv "$1" "$2"; }
st_good() { kv "$1" "${GREEN}✔${NC} $2"; }
st_warn() { kv "$1" "${YELLOW}⚠ $2${NC}"; ST_WARNINGS=$(( ST_WARNINGS + 1 )); }
st_bad()  { kv "$1" "${RED}✘ $2${NC}"; ST_PROBLEMS=$(( ST_PROBLEMS + 1 )); }

# usage_bar PERCENT  ->  coloured bar + percentage (yellow from 85%, red from 95%)
usage_bar() {
    local pct="$1" width=30 filled colour="$GREEN" full empty
    if (( pct > 100 )); then pct=100; fi
    filled=$(( pct * width / 100 ))
    if (( pct >= 95 )); then
        colour="$RED"
    elif (( pct >= 85 )); then
        colour="$YELLOW"
    fi
    full=$(printf '%*s' "$filled" '' | sed 's/ /█/g')
    empty=$(printf '%*s' $(( width - filled )) '' | sed 's/ /░/g')
    printf '%s%s%s%s%s %s%d%%%s' "$colour" "$full" "$NC" "$DIM" "$empty" "$colour" "$pct" "$NC"
}

# Creates, syncs and removes a small file. 0 = ok, 2 = failed, 3 = no answer in 10s
status_write_test() {
    local f="$1/.pbs-status-test" pid i
    ( : > "$f" && sync -d "$f" && rm -f "$f" ) 2>/dev/null &
    pid=$!
    for i in $(seq 1 10); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        return 3
    fi
    if wait "$pid"; then
        return 0
    fi
    return 2
}

# One installation = one monitor script in /usr/local/bin (it holds target, portal, mount path)
status_one() {
    local script="$1" TARGET="" PORTAL="" MOUNT_PATH=""
    local service_name src fstype opts disk disc state sid rt live rt_show
    local size used pct used_h size_h ds rc cutoff events last_line conf mode drop sess_up auth prov

    # shellcheck disable=SC1090
    source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH)=' "$script" || true)
    if [[ -z "$TARGET" || -z "$MOUNT_PATH" ]]; then
        echo
        panel_top "$(basename "$script")" "$YELLOW"
        panel_line "${YELLOW}Could not read the target and mount path from this monitor script.${NC}"
        panel_bottom
        ST_WARNINGS=$(( ST_WARNINGS + 1 ))
        return 0
    fi
    TARGET_IQN="$TARGET"
    PORTAL_IP="$PORTAL"
    service_name=$(basename "$MOUNT_PATH")
    KNOWN_NODES+=("${TARGET}|$(norm_portal "$PORTAL")")

    echo
    panel_top "iSCSI · ${MOUNT_PATH}"
    st_info "Target" "${TARGET##*:} ${DIM}(${PORTAL})${NC}"

    # --- session ---
    sess_up=0
    if session_active; then
        sess_up=1
        state=$(timeout 20 iscsiadm -m session -P 3 2>/dev/null | awk -v t="$TARGET" '
            /^[[:space:]]*Target:/ { in_t = ($2 == t) }
            in_t && /iSCSI Session State:/ { print $NF; exit }
        ' || true)
        if [[ -z "$state" || "$state" == "LOGGED_IN" ]]; then
            st_good "Session" "connected"
        else
            st_bad "Session" "${state} - the connection is down or recovering"
        fi
    else
        if [[ -f "/run/iscsi-monitor-${service_name}.state.authfail" ]]; then
            st_bad "Session" "not connected - the Synology REJECTED the login (CHAP)"
        else
            st_bad "Session" "not connected"
        fi
    fi

    # --- stored login ---
    auth=$(node_auth_state "$PORTAL" "$TARGET")
    case "$auth" in
        chap)
            st_good "Stored login" "CHAP, user $(node_field "$PORTAL" "$TARGET" node.session.auth.username)"
            ;;
        none)
            if [[ $sess_up -eq 1 ]]; then
                st_info "Stored login" "${DIM}no authentication${NC}"
            else
                st_warn "Stored login" "no CHAP login stored - if the target uses CHAP, run: $(self_name) --fix-login"
            fi
            ;;
        *)
            if [[ $sess_up -eq 1 ]]; then
                st_warn "Stored login" "CHAP login missing/incomplete - the NEXT reconnect will fail. Run: $(self_name) --fix-login"
            else
                st_bad "Stored login" "CHAP login missing/incomplete - the monitor cannot reconnect. Run: $(self_name) --fix-login"
            fi
            ;;
    esac

    # --- reconnect patience ---
    rt=$(iscsiadm -m node -T "$TARGET" -p "$PORTAL" 2>/dev/null \
        | awk -F' = ' '$1 == "node.session.timeo.replacement_timeout" { print $2 }' || true)
    sid=$(iscsiadm -m session 2>/dev/null | awk -v t="$TARGET" '$4 == t { gsub(/\[|\]/, "", $2); print $2; exit }' || true)
    live=""
    if [[ -n "$sid" ]]; then
        live=$(cat "/sys/class/iscsi_session/session${sid}/recovery_tmo" 2>/dev/null || true)
    fi
    rt_show="${live:-$rt}"
    if [[ "$rt_show" =~ ^[0-9]+$ ]] && (( rt_show >= 300 )); then
        st_good "Reconnect wait" "$(( rt_show / 60 )) minutes before I/O errors"
    elif [[ "$rt_show" =~ ^[0-9]+$ ]]; then
        st_warn "Reconnect wait" "only ${rt_show}s - a Synology restart can break the filesystem. Re-run the installer to raise it"
    else
        st_warn "Reconnect wait" "unknown"
    fi

    # --- mount ---
    src=$(findmnt -rn -M "$MOUNT_PATH" -o SOURCE 2>/dev/null || true)
    if [[ -z "$src" ]]; then
        st_bad "Mount" "not mounted"
    else
        fstype=$(findmnt -rn -M "$MOUNT_PATH" -o FSTYPE 2>/dev/null || true)
        opts=$(findmnt -rn -M "$MOUNT_PATH" -o OPTIONS 2>/dev/null || true)
        if [[ ",${opts}," == *,ro,* ]]; then
            st_bad "Mount" "READ-ONLY (${fstype}) - the filesystem hit an I/O error"
        else
            st_good "Mount" "${src} · ${fstype} · read-write"
        fi

        # --- space ---
        read -r size used _ < <(timeout 15 df -B1 --output=size,used,avail "$MOUNT_PATH" 2>/dev/null | tail -n 1) || true
        if [[ "${size:-}" =~ ^[0-9]+$ && "$size" -gt 0 ]]; then
            pct=$(( used * 100 / size ))
            used_h=$(numfmt --to=iec --suffix=B "$used" 2>/dev/null || echo "$used")
            size_h=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "$size")
            kv "Space" "$(usage_bar "$pct")  ${DIM}${used_h} of ${size_h}${NC}"
            if (( pct >= 95 )); then
                ST_PROBLEMS=$(( ST_PROBLEMS + 1 ))
                kv "" "${RED}✘ almost full - backups will fail${NC}"
            elif (( pct >= 85 )); then
                ST_WARNINGS=$(( ST_WARNINGS + 1 ))
                kv "" "${YELLOW}⚠ getting full - check prune and garbage collection${NC}"
            fi
        else
            st_warn "Space" "df did not answer in time"
        fi

        # --- write test ---
        if [[ ",${opts}," != *,ro,* ]]; then
            rc=0
            status_write_test "$MOUNT_PATH" || rc=$?
            case "$rc" in
                0) st_good "Write test" "a test file was written and removed" ;;
                3) st_bad "Write test" "no answer within 10 s - the storage is not responding" ;;
                *) st_bad "Write test" "failed" ;;
            esac
        fi

        # --- TRIM ---
        disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n 1 || true)
        if [[ -z "$disk" ]]; then
            disk=$(basename "$src")
        fi
        prov=$(lun_provisioning "$disk")
        disc=$(cat "/sys/block/${disk}/queue/discard_max_bytes" 2>/dev/null || echo 0)
        case "$prov" in
            thin)
                st_info "LUN type" "thin ${DIM}· space reclamation is on${NC}"
                if systemctl is-active --quiet fstrim.timer 2>/dev/null; then
                    st_good "TRIM" "weekly - deleted backups give space back to the Synology"
                else
                    st_warn "TRIM" "the LUN supports it, but fstrim.timer is not running"
                fi
                ;;
            thin-off)
                st_info "LUN type" "thin"
                st_warn "TRIM" "space reclamation is OFF on the Synology - deleted backups will not free space (DSM › SAN Manager › LUN › Edit)"
                ;;
            thick)
                st_info "LUN type" "thick ${DIM}· space is reserved on the NAS${NC}"
                st_info "TRIM" "${DIM}not needed on a thick LUN${NC}"
                ;;
            *)
                if [[ "$disc" =~ ^[0-9]+$ ]] && (( disc > 0 )); then
                    if systemctl is-active --quiet fstrim.timer 2>/dev/null; then
                        st_good "TRIM" "weekly ${DIM}(LUN type not reported - space only comes back on a thin LUN)${NC}"
                    else
                        st_warn "TRIM" "the LUN supports it, but fstrim.timer is not running"
                    fi
                else
                    st_info "TRIM" "${DIM}not supported by this LUN${NC}"
                fi
                ;;
        esac
    fi

    # --- datastore ---
    ds=$(awk -v p="$MOUNT_PATH" '
        /^datastore:/ { name = $2 }
        $1 == "path" && ($2 == p || index($2, p "/") == 1) { print name }
    ' "$DS_CFG" 2>/dev/null | paste -sd, - || true)
    if [[ -n "$ds" ]]; then
        if systemctl is-active --quiet proxmox-backup-proxy 2>/dev/null; then
            st_good "Datastore" "${ds} ${DIM}(PBS is running)${NC}"
        else
            st_bad "Datastore" "${ds} - but the PBS service (proxmox-backup-proxy) is not running"
        fi
    else
        st_info "Datastore" "${DIM}none on this LUN yet${NC}"
    fi

    # --- boot order ---
    drop="/etc/systemd/system/proxmox-backup-proxy.service.d/10-iscsi-${service_name}.conf"
    if [[ -f "$drop" ]]; then
        st_good "Boot order" "PBS starts after the mount"
    else
        st_warn "Boot order" "not configured - re-run the installer (v1.6+) to add it"
    fi

    # --- monitor ---
    if [[ -x "$script" ]] && crontab -l 2>/dev/null | grep -qF "$script"; then
        st_good "Monitor" "runs every minute"
    else
        st_bad "Monitor" "the cron job is missing"
    fi
    cutoff=$(date -d '24 hours ago' '+%F %T')
    events=0
    last_line=""
    if [[ -r /var/log/iscsi-monitor.log ]]; then
        events=$(awk -v c="$cutoff" 'substr($0, 1, 19) >= c' /var/log/iscsi-monitor.log \
            | grep -cE 'Failed|failed|Repairing|read-only|no answer|state is|REJECTED' || true)
        last_line=$(tail -n 1 /var/log/iscsi-monitor.log 2>/dev/null || true)
    fi
    if [[ "${events:-0}" -gt 0 ]]; then
        st_warn "Last 24 hours" "${events} problem event(s) in the monitor log"
    else
        st_good "Last 24 hours" "no problems logged"
    fi
    if [[ -n "$last_line" ]]; then
        kv "Last log line" "${DIM}$(trunc "$last_line" $(( $(term_cols) - 22 )))${NC}"
    fi

    # --- alerts ---
    conf="/etc/pbs-iscsi-monitor-${service_name}.conf"
    mode=$(sed -n "s/^NOTIFY_MODE=//p" "$conf" 2>/dev/null | head -n 1 || true)
    case "$mode" in
        url)  st_good "Alerts" "push message / webhook" ;;
        mail) st_good "Alerts" "email" ;;
        *)    st_info "Alerts" "${DIM}off - the monitor only writes to its log${NC}" ;;
    esac
    panel_bottom
}

# "pbs-post-install.sh" if the installed copy exists, otherwise how this script was started
self_name() {
    if [[ -x /usr/local/sbin/pbs-post-install.sh ]]; then
        echo "pbs-post-install.sh"
    else
        echo "$0"
    fi
}

# Panel with iSCSI records that no installation uses
status_stale_records() {
    local -a stale=()
    local rec portal iqn startup auth
    mapfile -t stale < <(find_stale_records)
    if [[ ${#stale[@]} -eq 0 ]]; then
        return 0
    fi
    echo
    panel_top "Other iSCSI records" "$YELLOW"
    for rec in "${stale[@]}"; do
        IFS='|' read -r portal iqn startup auth <<< "$rec"
        if [[ "$startup" == "automatic" && "$auth" != "chap" ]]; then
            st_warn "${iqn##*:}" "${portal} logs in at boot WITHOUT a valid CHAP login (failed logins in the Synology log)"
        else
            st_info "${iqn##*:}" "${DIM}${portal} · boot login: ${startup:-?} · CHAP: ${auth} · unused${NC}"
        fi
    done
    panel_blank
    panel_line "${DIM}Remove one:  iscsiadm -m node -T <target> -p <portal> -o delete${NC}"
    panel_bottom
}

run_status() {
    local -a scripts=()
    local s pbs_ver host_ip
    if [[ $EUID -ne 0 ]]; then
        echo "--status needs root (it talks to iscsiadm). Run:  sudo $0 --status" >&2
        return 2
    fi
    if [[ ! -t 1 ]]; then
        # Plain text when piped or run from cron
        RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; WHITE=""; DIM=""; BOLD=""; NC=""
    fi
    pbs_ver=$(proxmox-backup-manager versions 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)

    echo
    echo "  ${WHITE}PBS Post-Install${NC}  ${DIM}v${VERSION} · health check · $(date '+%F %H:%M')${NC}"
    echo "${CYAN}${RULE}${NC}"
    echo
    panel_top "This server"
    kv "Hostname" "$(hostname -f 2>/dev/null || hostname)  ${DIM}${host_ip}${NC}"
    kv "PBS" "${pbs_ver:-${YELLOW}not detected${NC}}"
    panel_bottom

    shopt -s nullglob
    scripts=(/usr/local/bin/check-iscsi-session-*.sh)
    shopt -u nullglob
    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo
        panel_top "No installation found" "$YELLOW"
        panel_line "No iSCSI monitor script exists on this server."
        panel_line "Run the installer without options to set it up."
        panel_bottom
        return 2
    fi
    KNOWN_NODES=()
    for s in "${scripts[@]}"; do
        status_one "$s"
    done
    status_stale_records

    echo
    if [[ $ST_PROBLEMS -gt 0 ]]; then
        echo "  ${RED}✘ ${ST_PROBLEMS} problem(s) found${NC}"
        echo "  ${DIM}Monitor log: /var/log/iscsi-monitor.log${NC}"
        echo
        return 1
    elif [[ $ST_WARNINGS -gt 0 ]]; then
        echo "  ${YELLOW}⚠ Working, but ${ST_WARNINGS} warning(s) - see above${NC}"
        echo
        return 0
    fi
    echo "  ${GREEN}✔ Everything looks healthy${NC}"
    echo
    return 0
}

# --fix-login: type the CHAP username/password again for an installed target.
# Use it when the Synology log shows "failed to login ... CHAP required but absent".
run_fix_login() {
    local -a scripts=() items=()
    local s choice=0 TARGET="" PORTAL="" MOUNT_PATH=""
    if [[ $EUID -ne 0 ]]; then
        echo "--fix-login needs root. Run:  sudo $0 --fix-login" >&2
        return 2
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "--fix-login is interactive - run it directly in a terminal." >&2
        return 2
    fi
    INSTALL_STARTED=1      # nothing to undo if this is cancelled
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    INITIATOR_IQN=$(awk -F= '/^InitiatorName=/ {print $2}' /etc/iscsi/initiatorname.iscsi 2>/dev/null || true)

    shopt -s nullglob
    scripts=(/usr/local/bin/check-iscsi-session-*.sh)
    shopt -u nullglob
    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo "No iSCSI installation found on this server (no monitor script in /usr/local/bin)." >&2
        return 2
    fi
    if [[ ${#scripts[@]} -gt 1 ]]; then
        for s in "${scripts[@]}"; do
            TARGET=""; PORTAL=""; MOUNT_PATH=""
            # shellcheck disable=SC1090
            source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH)=' "$s" || true)
            items+=("${MOUNT_PATH}|${TARGET}")
        done
        TARGET=""; PORTAL=""; MOUNT_PATH=""
        echo
        echo "  ${WHITE}Which installation should be fixed?${NC}"
        menu_select choice 0 "${items[@]}"
    fi
    # shellcheck disable=SC1090
    source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH)=' "${scripts[choice]}" || true)
    if [[ -z "$TARGET" || -z "$PORTAL" ]]; then
        echo "Could not read the target and portal from ${scripts[choice]}." >&2
        return 2
    fi
    TARGET_IQN="$TARGET"
    PORTAL_IP="$PORTAL"

    printf '\033[2J\033[H'
    render_banner
    echo
    panel_top "Fix the iSCSI login"
    kv "Target" "${TARGET}"
    kv "Synology" "${PORTAL}"
    kv "This server" "${INITIATOR_IQN:-unknown}"
    panel_blank
    panel_line "Type the CHAP username and password as set on the Synology:"
    panel_line "${DIM}SAN Manager › iSCSI › Target › Edit › Authentication (password: 12-16 characters)${NC}"
    panel_bottom

    ensure_iscsi_service
    create_node_record
    while true; do
        CHAP_MODE=1
        CHAP_KEEP=0
        echo
        ask_required CHAP_USER "CHAP username"
        ask_secret CHAP_PASS "CHAP password"
        apply_auth
        node_update node.startup automatic
        node_update node.session.timeo.replacement_timeout "$REPLACEMENT_TIMEOUT"
        ok "The CHAP login is saved"
        log_msg "fix-login: CHAP login re-entered for ${TARGET}"

        if session_active; then
            ok "The connection is already up - the new login is used at the next reconnect"
            rm -f /run/iscsi-monitor-*.state.authfail
            return 0
        fi
        echo
        run_quiet_soft "Logging in to ${TARGET_IQN##*:}" \
            timeout 30 iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" --login
        LOGIN_RC=$RUN_RC
        if [[ $LOGIN_RC -eq 0 || $LOGIN_RC -eq 15 ]]; then
            ok "Connected - the CHAP login works"
            rm -f /run/iscsi-monitor-*.state.authfail
            if [[ -n "$MOUNT_PATH" ]] && ! findmnt -rn -M "$MOUNT_PATH" >/dev/null 2>&1; then
                sleep 3
                run_quiet_soft "Mounting ${MOUNT_PATH}" timeout 60 mount "$MOUNT_PATH"
                if [[ $RUN_RC -ne 0 ]]; then
                    warn "Could not mount ${MOUNT_PATH} yet - the monitor retries every minute."
                fi
            fi
            echo
            echo "  ${DIM}Check everything with: $(self_name) --status${NC}"
            return 0
        fi
        show_login_error
        menu_select choice 0 "Enter the login again" "Quit|The login stays as typed; nothing else was changed"
        if [[ $choice -ne 0 ]]; then
            return 1
        fi
    done
}

# ===========================================================================
# DRIVE MANAGEMENT  (--add-drive / --remove-drive)
# ===========================================================================
# --add-drive: the normal setup, shortened to the drive: no repository, upgrade, popup or
# login-screen questions. Suggests a free mount path and datastore name for the next drive.
prepare_add_drive() {
    local n=2 cand
    DO_REPO=0; DO_UPGRADE=0; DO_NAG=0; DO_MOTD=0; DO_ISCSI=1; DO_DS=1
    while true; do
        cand="/mnt/synology${n}"
        if [[ ! -e "/usr/local/bin/check-iscsi-session-synology${n}.sh" && ! -e "$cand" ]] \
            && ! awk -v p="$cand" '!/^[[:space:]]*#/ && $2 == p { f = 1 } END { exit !f }' /etc/fstab; then
            break
        fi
        n=$(( n + 1 ))
    done
    MOUNT_PATH="$cand"
    DS_NAME="synology-backup-${n}"
}

# Datastores whose path is the mount point or a folder below it
datastores_on() {
    awk -v p="$1" '
        /^datastore:/ { name = $2 }
        $1 == "path" && ($2 == p || index($2, p "/") == 1) { print name }
    ' "$DS_CFG" 2>/dev/null || true
}

# Number of PBS tasks that are running right now and mention "$1" (a datastore). "?" = cannot tell.
running_tasks_for() {
    local out
    if ! out=$(timeout 20 proxmox-backup-manager task list --output-format json 2>/dev/null); then
        echo "?"
        return 0
    fi
    grep -oF "$1" <<< "$out" | wc -l || true
}

# --remove-drive: takes one drive away again, step by step, in the safe order.
# It NEVER erases data on the LUN and never touches anything on the Synology.
run_remove_drive() {
    local -a scripts=() items=()
    local f s TARGET PORTAL MOUNT_PATH name script choice ds_list ds busy shared=0 tmp
    local pbs_stopped=0 confirm users failed=0

    if [[ $EUID -ne 0 ]]; then
        echo "--remove-drive needs root. Run:  sudo $0 --remove-drive" >&2
        return 2
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "--remove-drive is interactive - run it in a terminal." >&2
        return 2
    fi
    touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
    INSTALL_STARTED=1
    echo "=== remove-drive v${VERSION} started $(date '+%F %T')" >> "$LOG_FILE"

    for f in /usr/local/bin/check-iscsi-session-*.sh; do
        if [[ -f "$f" ]]; then scripts+=("$f"); fi
    done
    printf '\033[2J\033[H'
    CURRENT_TASK="Remove a drive"
    render_banner
    echo
    if [[ ${#scripts[@]} -eq 0 ]]; then
        info "No drive set up by this installer was found - nothing to remove."
        return 0
    fi

    # ---- which drive?
    for s in "${scripts[@]}"; do
        TARGET=""; PORTAL=""; MOUNT_PATH=""
        # shellcheck disable=SC1090
        source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH)=' "$s")
        ds_list=$(datastores_on "$MOUNT_PATH" | paste -sd, - || true)
        items+=("$(basename "$MOUNT_PATH")|${MOUNT_PATH} · ${TARGET##*:} · datastore: ${ds_list:-none}")
    done
    items+=("Cancel|Nothing is changed")
    echo "  ${WHITE}Which drive do you want to remove?${NC}"
    menu_select choice 0 "${items[@]}"
    if [[ $choice -ge ${#scripts[@]} ]]; then
        echo "  ${YELLOW}Cancelled - nothing was changed.${NC}"
        return 0
    fi
    script="${scripts[choice]}"
    TARGET=""; PORTAL=""; MOUNT_PATH=""
    # shellcheck disable=SC1090
    source <(grep -E '^(TARGET|PORTAL|MOUNT_PATH)=' "$script")
    if [[ -z "$TARGET" || -z "$PORTAL" || -z "$MOUNT_PATH" ]]; then
        err "Could not read the drive details from ${script} - nothing was changed."
        return 1
    fi
    name=$(basename "$MOUNT_PATH")
    ds_list=$(datastores_on "$MOUNT_PATH" | paste -sd' ' - || true)
    for f in "${scripts[@]}"; do
        if [[ "$f" != "$script" ]] && grep -qF "TARGET=$(printf '%q' "$TARGET")" "$f"; then
            shared=1
        fi
    done

    # ---- is it safe right now?
    for ds in $ds_list; do
        busy=$(running_tasks_for "$ds")
        if [[ "$busy" == "?" ]]; then
            warn "Could not ask PBS whether a backup is running on '${ds}'. Check the web UI (Administration › Tasks) before you continue."
        elif [[ "$busy" -gt 0 ]]; then
            err "A task is running on datastore '${ds}' (backup, verify, garbage collection or sync). Wait for it to finish, then run this again. Nothing was changed."
            return 1
        fi
    done

    # ---- the plan
    echo
    panel_top "Remove drive · ${name}" "$YELLOW"
    kv "Mount path" "$MOUNT_PATH"
    kv "Target" "$TARGET"
    kv "Synology" "$PORTAL"
    kv "PBS datastore" "${ds_list:-${DIM}none on this drive${NC}}"
    panel_blank
    panel_line "${WHITE}This will:${NC}"
    if [[ -n "$ds_list" ]]; then
        panel_line "  1. remove the datastore from PBS ${DIM}(the backup files stay on the LUN)${NC}"
    else
        panel_line "  1. ${DIM}(no PBS datastore on this drive)${NC}"
    fi
    panel_line "  2. stop the monitor and its cron job"
    panel_line "  3. unmount ${MOUNT_PATH} and remove its /etc/fstab line ${DIM}(a copy is kept)${NC}"
    panel_line "  4. remove the boot-order file for PBS"
    if [[ $shared -eq 1 ]]; then
        panel_line "  5. ${YELLOW}keep the iSCSI login${NC} ${DIM}- another drive uses the same target${NC}"
    else
        panel_line "  5. log out of the target and delete its saved settings on this server"
    fi
    panel_blank
    panel_line "${WHITE}It will NOT:${NC} erase anything on the LUN, or change anything on the Synology."
    panel_blank
    panel_line "${DIM}Afterwards you remove the storage entry in Proxmox VE and, if you want the${NC}"
    panel_line "${DIM}space back, the LUN on the Synology. You get a reminder at the end.${NC}"
    panel_bottom
    echo
    echo "  ${RED}⚠  Backups on this datastore will no longer be reachable from PBS.${NC}"
    ask_input confirm "Type the drive name (${name}) to continue, or press Enter to cancel"
    if [[ "$confirm" != "$name" ]]; then
        echo "  ${YELLOW}Cancelled - nothing was changed.${NC}"
        return 0
    fi
    echo

    # ---- 1. PBS datastore (the files stay: no --destroy-data)
    for ds in $ds_list; do
        run_quiet_soft "Removing datastore '${ds}' from PBS" proxmox-backup-manager datastore remove "$ds"
        if [[ $RUN_RC -ne 0 ]]; then
            err "PBS could not remove '${ds}' (exit code ${RUN_RC}). Nothing else was changed. Log: ${LOG_FILE}"
            return 1
        fi
        ok "Datastore '${ds}' removed from PBS ${DIM}(files kept on the LUN)${NC}"
    done

    # ---- 2. monitor: cron first, so it cannot "repair" the drive we are taking away
    tmp=$(mktemp)
    cron_without_monitor "$name" > "$tmp"
    crontab "$tmp"
    rm -f "$tmp"
    flock -w 30 "/run/lock/iscsi-monitor-${name}.lock" true 2>/dev/null || true
    ok "Monitor stopped (cron job removed)"

    # ---- 3. unmount
    if mountpoint -q "$MOUNT_PATH"; then
        sync
        if ! umount "$MOUNT_PATH" >> "$LOG_FILE" 2>&1; then
            warn "${MOUNT_PATH} is busy - something still uses it:"
            users=$(fuser -vm "$MOUNT_PATH" 2>&1 | head -n 8 || true)
            if [[ -n "$users" ]]; then
                while IFS= read -r f; do echo "    ${DIM}${f}${NC}"; done <<< "$users"
            fi
            menu_select choice 0 \
                "Stop PBS for a moment and try again|PBS is started again afterwards" \
                "Leave the drive mounted|Stop here - you can run Remove again later"
            if [[ $choice -eq 0 ]]; then
                systemctl stop proxmox-backup-proxy proxmox-backup >> "$LOG_FILE" 2>&1 || true
                pbs_stopped=1
                sleep 2
                umount "$MOUNT_PATH" >> "$LOG_FILE" 2>&1 || true
            fi
        fi
        if mountpoint -q "$MOUNT_PATH"; then
            if [[ $pbs_stopped -eq 1 ]]; then
                systemctl start proxmox-backup proxmox-backup-proxy >> "$LOG_FILE" 2>&1 || true
            fi
            tmp=$(mktemp)
            { cron_without_monitor "$name"; echo "*/1 * * * * ${script} # iSCSI monitor for ${name}"; } > "$tmp"
            crontab "$tmp"
            rm -f "$tmp"
            echo
            err "${MOUNT_PATH} is still mounted. Stopped here:"
            echo "    ${DIM}• the datastore is removed from PBS${NC}"
            echo "    ${DIM}• the mount, fstab line and iSCSI login are untouched, and the monitor runs again${NC}"
            echo "    ${DIM}Close whatever uses the drive, then run Remove again (Drives › Remove a drive).${NC}"
            return 1
        fi
    fi
    ok "Unmounted ${MOUNT_PATH}"

    # ---- fstab (a copy is kept)
    if awk -v p="$MOUNT_PATH" '!/^[[:space:]]*#/ && $2 == p { f = 1 } END { exit !f }' /etc/fstab; then
        cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
        tmp=$(mktemp)
        awk -v p="$MOUNT_PATH" '/^[[:space:]]*#/ || $2 != p' /etc/fstab > "$tmp"
        cat "$tmp" > /etc/fstab
        rm -f "$tmp"
        ok "Removed the /etc/fstab line ${DIM}(copy: /etc/fstab.backup.*)${NC}"
    fi

    # ---- the empty mount directory (made immutable by the installer)
    if [[ -d "$MOUNT_PATH" ]]; then
        chattr -i "$MOUNT_PATH" 2>/dev/null || true
        if [[ -z "$(ls -A "$MOUNT_PATH" 2>/dev/null)" ]]; then
            rmdir "$MOUNT_PATH" 2>/dev/null && ok "Removed the empty directory ${MOUNT_PATH}"
        else
            warn "${MOUNT_PATH} is not empty (files on the local disk) - left in place"
        fi
    fi

    # ---- boot order, monitor files
    for f in proxmox-backup proxmox-backup-proxy; do
        rm -f "/etc/systemd/system/${f}.service.d/10-iscsi-${name}.conf"
        rmdir "/etc/systemd/system/${f}.service.d" 2>/dev/null || true
    done
    systemctl daemon-reload
    rm -f "$script" "/etc/pbs-iscsi-monitor-${name}.conf" "/run/lock/iscsi-monitor-${name}.lock" \
          "/run/iscsi-monitor-${name}.state" "/run/iscsi-monitor-${name}.state."*
    ok "Monitor files and boot-order file removed"

    # ---- iSCSI login: only when no other drive uses the same target
    if [[ $shared -eq 1 ]]; then
        info "The iSCSI login is kept - another drive uses the same target."
    else
        run_quiet_soft "Logging out of the target" timeout 60 iscsiadm -m node -T "$TARGET" -p "$PORTAL" --logout
        if [[ $RUN_RC -ne 0 && $RUN_RC -ne 21 ]]; then
            warn "Logout did not finish cleanly (exit code ${RUN_RC}) - see ${LOG_FILE}"
            failed=1
        fi
        if iscsiadm -m node -T "$TARGET" -p "$PORTAL" -o delete >> "$LOG_FILE" 2>&1; then
            ok "iSCSI settings for the target deleted on this server"
        else
            warn "Could not delete the saved iSCSI settings - remove them with: iscsiadm -m node -T ${TARGET} -p ${PORTAL} -o delete"
            failed=1
        fi
    fi

    if [[ $pbs_stopped -eq 1 ]]; then
        systemctl start proxmox-backup proxmox-backup-proxy >> "$LOG_FILE" 2>&1 || true
        ok "PBS started again"
    fi
    echo "OK    drive ${name} removed" >> "$LOG_FILE"

    echo
    if [[ $failed -eq 0 ]]; then
        echo "  ${GREEN}✔  Drive '${name}' is removed from this server.${NC}"
    else
        echo "  ${YELLOW}⚠  Drive '${name}' is removed, with the notes above.${NC}"
    fi
    echo
    panel_top "Still to do by hand" "$GREEN"
    panel_line "${WHITE}Proxmox VE${NC}   Datacenter › Storage: remove the storage entry that pointed to"
    panel_line "              ${ds_list:-this datastore}, and check your backup jobs."
    panel_line "${WHITE}Synology${NC}     Only if you want the space back: SAN Manager › LUN › delete the LUN"
    panel_line "              (this deletes the backups on it for good), then the target if it is unused."
    panel_line "${DIM}Until you delete the LUN on the Synology, the backups are still on it.${NC}"
    panel_bottom
    echo
}

usage() {
    cat <<EOF
PBS Post-Install v${VERSION}

  ./pbs-post-install.sh              interactive installer (run as root, in a terminal)
  ./pbs-post-install.sh --status     health dashboard - changes nothing
                                     exit code 0 = healthy, 1 = problem found, 2 = not installed
  ./pbs-post-install.sh --fix-login  type the CHAP username/password again for an installed
                                     target (Synology log: "CHAP required but absent")
  ./pbs-post-install.sh --add-drive  connect one more Synology LUN (own mount path, datastore, monitor)
  ./pbs-post-install.sh --remove-drive  take a drive away again (datastore, monitor, mount, iSCSI login)
  ./pbs-post-install.sh --motd       install / update only the login dashboard + menu
  ./pbs-post-install.sh --motd-remove  remove the login screen (restores /etc/motd)
  ./pbs-post-install.sh --motd-update  update login screen + installer copy, keep all settings
                                     (normally started for you by: pbs-motd --update-installer)
  ./pbs-post-install.sh --version
  ./pbs-post-install.sh --help
EOF
}

# ===========================================================================
# MAIN
# ===========================================================================
main() {
    local rc=0
    case "${1:-}" in
        "") ;;
        --add-drive) ADD_DRIVE=1 ;;
        --remove-drive)
            run_remove_drive || rc=$?
            exit "$rc"
            ;;
        --status|-s)
            run_status || rc=$?
            exit "$rc"
            ;;
        --fix-login)
            run_fix_login || rc=$?
            exit "$rc"
            ;;
        --motd)
            run_motd_only || rc=$?
            exit "$rc"
            ;;
        --motd-remove)
            run_motd_remove || rc=$?
            exit "$rc"
            ;;
        --motd-update)
            run_motd_update || rc=$?
            exit "$rc"
            ;;
        --version|-V)
            echo "pbs-post-install v${VERSION}"
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    preflight
    if [[ $ADD_DRIVE -eq 1 ]]; then
        prepare_add_drive
    fi
    run_setup
    run_install
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi