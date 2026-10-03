#!/bin/bash
# =============================================================================
#   PBS Post-Install  ·  Proxmox Backup Server + Synology iSCSI
# =============================================================================
# Safe PBS post-install script with iSCSI setup, so you can back up via iSCSI
# to your Synology NAS.
# 
# Thanks to Derek Seaman's Tech Blog who inspired me to make this.
#
# Version 1.4  10/3-2026
# Author MorphyDK

set -eE
export LC_ALL=C.UTF-8

VERSION="1.4"
LOG_FILE="/var/log/pbs-post-install.log"
FS_LABEL="pbs-data"
FOUR_TIB=4398046511104

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

DEVICE_PATH=""
LUN_SIZE=""
LUN_SIZE_H=""
LUN_WWN=""
LUN_MODEL=""
LUN_DISCARD=0
LUN_EMPTY=0
LUN_LAYOUT=""
PROBE_NODE=""
PROBE_FS=""
PROBE_UUID=""
PROBE_LABEL=""
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
SETUP_NAMES=("Welcome" "Options" "iSCSI tools" "Synology guide" "Connection" "LUN & filesystem" "Mount & datastore" "Review")

STEP_NAMES=(
    "APT repositories"
    "System upgrade"
    "Connect to iSCSI target"
    "Prepare disk"
    "Mount via /etc/fstab"
    "Monitoring & TRIM"
    "PBS datastore"
    "Subscription popup"
    "Finish"
)
S_REPO=0; S_UPG=1; S_CONN=2; S_DISK=3; S_MOUNT=4; S_MON=5; S_DS=6; S_NAG=7; S_FIN=8
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
hide_cursor() { printf '\e[?25l'; }
show_cursor() { printf '\e[?25h'; }

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
    el=$(( SECONDS - INSTALL_START ))
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
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 start=$SECONDS
    { echo; echo "=== $(date '+%F %T')  $desc"; } >> "$LOG_FILE"
    hide_cursor
    "$@" </dev/null >> "$LOG_FILE" 2>&1 &
    BG_PID=$!
    while kill -0 "$BG_PID" 2>/dev/null; do
        printf '\r  %s%s%s %s %s(%ds)%s\033[K' "$CYAN" "${frames[i % 10]}" "$NC" "$desc" "$DIM" $(( SECONDS - start )) "$NC"
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
        printf '  %s✔%s %s %s(%ds)%s\n' "$GREEN" "$NC" "$desc" "$DIM" $(( SECONDS - start )) "$NC"
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

apt_update() {
    run_quiet_soft "Updating package lists" apt-get -q update
    if [[ $RUN_RC -ne 0 ]]; then
        APT_WARN="apt update had warnings"
        warn "apt update reported warnings (see the log) - continuing"
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
    if ! iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" >/dev/null 2>&1; then
        iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" -o new >/dev/null
        NODES_CREATED+=("${TARGET_IQN}|${PORTAL_IP}")
    fi
}

# Writes the authentication settings into the node record (never on screen or in the log)
apply_auth() {
    if [[ $CHAP_MODE -eq 1 ]]; then
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

# Prints the /dev/sdX that is attached (and running) for $TARGET_IQN
get_target_device() {
    iscsiadm -m session -P 3 2>/dev/null | awk -v t="$TARGET_IQN" '
        /^[[:space:]]*Target:/ { in_t = ($2 == t) }
        in_t && /Attached scsi disk/ && /State: running/ { print "/dev/" $4; exit }
    ' || true
}

# Waits (max ~20s, with one rescan) for the target's disk to show up
wait_for_device() {
    local dev attempt rescanned=0
    for attempt in $(seq 1 20); do
        dev=$(get_target_device)
        if [[ -n "$dev" && -b "$dev" ]]; then
            echo "$dev"
            return 0
        fi
        if [[ $attempt -eq 10 && $rescanned -eq 0 ]]; then
            iscsiadm -m session --rescan >/dev/null 2>&1 || true
            rescanned=1
        fi
        sleep 1
    done
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
probe_lun() {
    local dev="$DEVICE_PATH" base disc devfs pttype t p opts dir chunks ds_root
    local -a parts=() candidates=()
    base=$(basename "$dev")

    PROBE_NODE=""; PROBE_FS=""; PROBE_UUID=""; PROBE_LABEL=""; PROBE_OTHER=""
    PROBE_MOUNTED_AT=""; PROBE_INSPECTED=0; PROBE_PBS=0; PROBE_PBS_SUB=""
    PROBE_GROUPS=0; PROBE_LATEST=""; PROBE_USED=""; PROBE_FILES=0

    LUN_SIZE=$(lsblk -dnbo SIZE "$dev" 2>/dev/null | tr -d ' ' || true)
    LUN_SIZE_H=$(lsblk -dno SIZE "$dev" 2>/dev/null | tr -d ' ' || true)
    LUN_WWN=$(lsblk -dno WWN "$dev" 2>/dev/null | tr -d ' ' || true)
    LUN_MODEL=$(lsblk -dno VENDOR,MODEL "$dev" 2>/dev/null | xargs || true)
    disc=$(cat "/sys/block/${base}/queue/discard_max_bytes" 2>/dev/null || echo 0)
    LUN_DISCARD=0
    if [[ "$disc" =~ ^[0-9]+$ ]] && (( disc > 0 )); then
        LUN_DISCARD=1
    fi

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
    PROBE_LABEL=$(blkid -p -s LABEL -o value "$PROBE_NODE" 2>/dev/null || true)
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
    if [[ $LUN_DISCARD -eq 1 ]]; then
        kv "Reclamation" "${GREEN}TRIM supported${NC} ${DIM}(thin LUN with space reclamation)${NC}"
    else
        kv "Reclamation" "${YELLOW}no TRIM${NC} ${DIM}(thick LUN, or space reclamation is off)${NC}"
    fi

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
        exit 1
    fi
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    echo "=== PBS post-install v${VERSION} started $(date '+%F %T')" >> "$LOG_FILE"

    OS_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
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
        )
        CL_HINTS=(
            "Disables the enterprise repo (needs a paid subscription) and enables the free repo"
            "Recommended on a fresh install - can take a few minutes"
            "Installs open-iscsi, connects, inspects and mounts the LUN"
            "Registers the storage in PBS so backups can be stored there"
            "Hides the \"No valid subscription\" message at login - kept after updates"
        )
        CL_STATE=("$DO_REPO" "$DO_UPGRADE" "$DO_ISCSI" "$DO_DS" "$DO_NAG")
        checklist_select
        DO_REPO=${CL_STATE[0]}
        DO_UPGRADE=${CL_STATE[1]}
        DO_ISCSI=${CL_STATE[2]}
        DO_DS=${CL_STATE[3]}
        DO_NAG=${CL_STATE[4]}
        if [[ $(( DO_REPO + DO_UPGRADE + DO_ISCSI + DO_DS + DO_NAG )) -gt 0 ]]; then
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
    sleep 2
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

ask_chap() {
    local choice
    echo
    echo "  ${WHITE}Authentication${NC}"
    menu_select choice $(( CHAP_MODE == 1 ? 0 : 1 )) \
        "CHAP - username + password (recommended)|As set on the Synology: Target › Edit › Authentication" \
        "No authentication|Only if CHAP is disabled on the target"
    if [[ $choice -eq 0 ]]; then
        CHAP_MODE=1
        ask_required CHAP_USER "CHAP username" "" "$CHAP_USER"
        ask_secret CHAP_PASS "CHAP password"
        if (( ${#CHAP_PASS} < 12 || ${#CHAP_PASS} > 16 )); then
            warn "Synology CHAP passwords are normally 12-16 characters - double-check it."
        fi
    else
        CHAP_MODE=0
        CHAP_USER=""
        CHAP_PASS=""
    fi
}

test_login() {
    create_node_record
    apply_auth
    node_update node.startup manual
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
            return 0
        fi
        ask_chap
        while true; do
            if test_login; then
                return 0
            fi
            show_login_error
            menu_select choice 0 \
                "Re-enter the login details|Username, password or authentication type" \
                "Try again|After fixing something on the Synology" \
                "Choose another target|Back to the target list" \
                "Quit|No disks have been touched"
            case "$choice" in
                0) ask_chap ;;
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
    local choice keep_label
    while true; do
        render_setup 5
        info "Waiting for the LUN to appear..."
        DEVICE_PATH=$(wait_for_device) || DEVICE_PATH=""
        if [[ -n "$DEVICE_PATH" ]]; then
            break
        fi
        err "The login worked, but no disk appeared."
        echo "    ${YELLOW}Most likely no LUN is mapped to this target on the Synology.${NC}"
        menu_select choice 0 "Try again|After mapping a LUN to the target" "Quit"
        if [[ $choice -ne 0 ]]; then quit_clean; fi
        iscsiadm -m session --rescan >/dev/null 2>&1 || true
    done
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

setup_mount_ds() {
    if [[ $DO_ISCSI -eq 0 && $DO_DS -eq 0 ]]; then
        return 0
    fi
    render_setup 6
    if [[ $DO_ISCSI -eq 1 ]]; then
        if [[ "$DISK_ACTION" == "mounted" ]]; then
            MOUNT_PATH="$PROBE_MOUNTED_AT"
            ok "The LUN stays mounted at ${MOUNT_PATH}"
        else
            ask_mount_path
        fi
    fi
    if [[ $DO_DS -eq 1 ]]; then
        setup_datastore_questions
    fi
}

setup_review() {
    local choice trim_txt=""
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
        kv "LUN" "${LUN_SIZE_H} · $( [[ $LUN_DISCARD -eq 1 ]] && echo 'TRIM supported' || echo 'no TRIM' )"
        case "$DISK_ACTION" in
            new)     kv "Disk" "${GREEN}create GPT partition + ${FS_TYPE}${NC}" ;;
            format)  kv "Disk" "${RED}ERASE the LUN and format it as ${FS_TYPE}${NC}" ;;
            keep)    kv "Disk" "${GREEN}keep the existing ${FS_TYPE} - no data is touched${NC}" ;;
            mounted) kv "Disk" "${GREEN}already mounted - unchanged${NC}" ;;
        esac
        kv "Mount path" "$MOUNT_PATH"
        if [[ $LUN_DISCARD -eq 1 ]]; then trim_txt=" · weekly TRIM"; fi
        kv "Monitoring" "reconnect check every minute${trim_txt}"
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
    setup_welcome
    while true; do
        setup_options
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
    shopt -s nullglob
    for f in /etc/apt/sources.list.d/pbs-enterprise*.list; do
        sed -i 's/^[[:space:]]*deb /# deb /' "$f"
        ok "Disabled $(basename "$f")"
    done
    for f in /etc/apt/sources.list.d/pbs-enterprise*.sources; do
        if grep -qi '^Enabled:' "$f"; then
            sed -i 's/^Enabled:.*/Enabled: false/I' "$f"
        else
            echo "Enabled: false" >> "$f"
        fi
        ok "Disabled $(basename "$f")"
    done
    shopt -u nullglob
    if [[ -f /etc/apt/sources.list ]] && grep -q '^[[:space:]]*deb .*pbs-enterprise' /etc/apt/sources.list; then
        sed -i '/pbs-enterprise/s/^[[:space:]]*deb /# deb /' /etc/apt/sources.list
        ok "Disabled the enterprise line in sources.list"
    fi

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
    local dev_size dev_wwn
    begin_step $S_CONN
    ensure_iscsi_service
    create_node_record
    apply_auth
    node_update node.startup automatic
    ok "Only this target is set to log in automatically at boot"

    if session_active; then
        ok "Session already active"
    else
        run_quiet_soft "Logging in to the target" \
            timeout 30 iscsiadm -m node -T "$TARGET_IQN" -p "$PORTAL_IP" --login
        if [[ $RUN_RC -ne 0 && $RUN_RC -ne 15 ]]; then
            fatal "Login failed (exit code ${RUN_RC}) even though the test during setup worked."
        fi
    fi

    info "Waiting for the disk to appear..."
    DEVICE_PATH=$(wait_for_device) || DEVICE_PATH=""
    if [[ -z "$DEVICE_PATH" ]]; then
        fatal "Could not detect a running iSCSI disk for target ${TARGET_IQN}."
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
        run_quiet "Formatting ${PARTITION} as XFS" mkfs.xfs -f -L "$FS_LABEL" "$PARTITION"
    else
        run_quiet "Formatting ${PARTITION} as ext4 (large LUNs take a while)" \
            mkfs.ext4 -F -m 0 -L "$FS_LABEL" "$PARTITION"
    fi
    udevadm settle >/dev/null 2>&1 || true

    UUID=$(blkid -p -s UUID -o value "$PARTITION" 2>/dev/null || true)
    if [[ -z "$UUID" ]]; then
        fatal "Cannot determine the UUID of ${PARTITION}"
    fi
    finish_step $S_DISK "${FS_TYPE} on ${PARTITION}"
}

step_mount() {
    local unit unit_name tmp_fstab service_name
    begin_step $S_MOUNT
    FSTAB_ENTRY="UUID=${UUID} ${MOUNT_PATH} ${FS_TYPE} defaults,_netdev,nofail,x-systemd.device-timeout=30 0 0"

    if [[ "$DISK_ACTION" == "mounted" ]]; then
        if awk -v p="$MOUNT_PATH" '!/^[[:space:]]*#/ && $2 == p { f = 1 } END { exit !f }' /etc/fstab; then
            ok "Already mounted and listed in /etc/fstab"
            FSTAB_ENTRY=$(awk -v p="$MOUNT_PATH" '!/^[[:space:]]*#/ && $2 == p' /etc/fstab | head -n 1)
        else
            cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
            echo "$FSTAB_ENTRY" >> /etc/fstab
            systemctl daemon-reload
            ok "Added the missing /etc/fstab entry (backup saved)"
        fi
        finish_step $S_MOUNT "$MOUNT_PATH (unchanged)"
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

step_monitor() {
    local service_name cron_job tmp_cron detail="reconnect check every minute"
    begin_step $S_MON
    service_name=$(basename "$MOUNT_PATH")
    CHECK_ISCSI_SCRIPT="/usr/local/bin/check-iscsi-session-${service_name}.sh"
    {
        echo '#!/bin/bash'
        echo "# Auto-generated iSCSI session and mount monitor for $service_name"
        printf 'TARGET=%q\n' "$TARGET_IQN"
        printf 'PORTAL=%q\n' "$PORTAL_IP"
        printf 'MOUNT_PATH=%q\n' "$MOUNT_PATH"
        printf 'LOCK_FILE=%q\n' "/run/lock/iscsi-monitor-${service_name}.lock"
        cat <<'MONITOR_EOF'
LOG_FILE="/var/log/iscsi-monitor.log"

# Never run two copies at once (cron fires every minute)
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

check_and_restore_mount() {
    if ! mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
        log_message "Mount point $MOUNT_PATH not mounted. Attempting to mount..."
        if mount "$MOUNT_PATH" 2>/dev/null; then
            log_message "Successfully mounted $MOUNT_PATH"
        else
            log_message "Failed to mount $MOUNT_PATH"
        fi
    fi
}

# Exact IQN match (field 4 of "iscsiadm -m session")
if ! iscsiadm -m session 2>/dev/null | awk -v t="$TARGET" '$4 == t { f = 1 } END { exit !f }'; then
    log_message "iSCSI session for $TARGET not found. Attempting to reconnect..."
    if iscsiadm -m node -T "$TARGET" -p "$PORTAL" --login 2>/dev/null; then
        log_message "Successfully reconnected to $TARGET"
        sleep 2
        check_and_restore_mount
    else
        log_message "Failed to reconnect to $TARGET"
    fi
else
    # Session exists - check its state ("iSCSI Session State: LOGGED_IN" when healthy)
    session_state=$(iscsiadm -m session -P 3 2>/dev/null | awk -v t="$TARGET" '
        /^[[:space:]]*Target:/ { in_t = ($2 == t) }
        in_t && /iSCSI Session State:/ { print $NF; exit }
    ')
    if [[ -n "$session_state" && "$session_state" != "LOGGED_IN" ]]; then
        log_message "iSCSI session for $TARGET exists but state is $session_state"
    fi
    check_and_restore_mount
fi
MONITOR_EOF
    } > "$CHECK_ISCSI_SCRIPT"
    chmod +x "$CHECK_ISCSI_SCRIPT"

    cron_job="*/1 * * * * $CHECK_ISCSI_SCRIPT # iSCSI monitor for $service_name"
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "# iSCSI monitor for $service_name" > "$tmp_cron" || true
    echo "$cron_job" >> "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"
    ok "Monitor installed: ${CHECK_ISCSI_SCRIPT}"

    if [[ $LUN_DISCARD -eq 1 ]]; then
        run_quiet_soft "Enabling weekly TRIM (space reclamation)" systemctl enable --now fstrim.timer
        if [[ $RUN_RC -eq 0 ]]; then
            detail+=" · weekly TRIM"
        fi
        if [[ "$DISK_ACTION" == "keep" ]]; then
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
    cat > /usr/local/bin/pbs-remove-nag.sh <<'NAG_EOF'
#!/bin/bash
# Removes the "No valid subscription" popup from the PBS web UI
# (installed by pbs-post-install.sh, re-run by /etc/apt/apt.conf.d/99-pbs-no-nag)
# Undo: rm /etc/apt/apt.conf.d/99-pbs-no-nag && apt reinstall proxmox-widget-toolkit
JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
[ -f "$JS" ] || exit 0
grep -q 'NO-NAG' "$JS" && exit 0
sed -i -E 's/(checked_command: function\(orig_cmd\) \{)/\1 orig_cmd(); return; \/\/ NO-NAG/' "$JS"
if grep -q 'NO-NAG' "$JS"; then
    echo "Subscription popup removed"
else
    echo "Subscription popup: pattern not found - the UI code may have changed"
fi
NAG_EOF
    chmod +x /usr/local/bin/pbs-remove-nag.sh
    echo 'DPkg::Post-Invoke { "/usr/local/bin/pbs-remove-nag.sh || true"; };' > /etc/apt/apt.conf.d/99-pbs-no-nag
    ok "Patch script and apt hook installed (re-applied after every update)"
    run_quiet_soft "Patching the web interface" /usr/local/bin/pbs-remove-nag.sh
    if grep -q 'NO-NAG' "$js" 2>/dev/null; then
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
    el=$(( SECONDS - INSTALL_START ))
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
    INSTALL_START=$SECONDS
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
    step_finish
}

# ===========================================================================
# MAIN
# ===========================================================================
main() {
    preflight
    run_setup
    run_install
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
