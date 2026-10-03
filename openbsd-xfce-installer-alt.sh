#!/bin/sh

###############################################################################
# OpenBSD 7.9 XFCE Auto Installer (alt)
#
# Supported:
#   - OpenBSD 7.9
#   - amd64
#   - i386
#
# Features:
#   - Architecture detection
#   - Idempotent package installation
#   - Mandatory / optional packages
#   - Retry failed package installation
#   - Partial package detection
#   - pkg_check verification
#   - Xenodm configuration
#   - D-Bus/messagebus detection
#   - User .xsession configuration
#   - Backup existing configuration
#   - VM detection
#
###############################################################################

set -u

SCRIPT_NAME="OpenBSD XFCE Installer (alt)"

###############################################################################
# Colors
###############################################################################

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
RESET="$(printf '\033[0m')"

###############################################################################
# Logging
###############################################################################

log() {
    printf "%s[INFO]%s %s\n" "$BLUE" "$RESET" "$*"
}

ok() {
    printf "%s[ OK ]%s %s\n" "$GREEN" "$RESET" "$*"
}

warn() {
    printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$*"
}

error() {
    printf "%s[ERROR]%s %s\n" "$RED" "$RESET" "$*" >&2
}

die() {
    error "$*"
    exit 1
}

###############################################################################
# Root check
###############################################################################

if [ "$(id -u)" -ne 0 ]; then
    die "Run this script as root or with doas."
fi

###############################################################################
# OS detection
###############################################################################

OS_NAME="$(uname -s)"
OS_RELEASE="$(uname -r)"
ARCH="$(machine -a)"

[ "$OS_NAME" = "OpenBSD" ] || die "This script is for OpenBSD only."

case "$OS_RELEASE" in
    7.9)
        ;;
    *)
        die "Unsupported OpenBSD version: $OS_RELEASE
Supported version: OpenBSD 7.9"
        ;;
esac

case "$ARCH" in
    amd64|i386)
        ;;
    *)
        die "Unsupported architecture: $ARCH
Supported architectures: amd64, i386"
        ;;
esac

###############################################################################
# Banner
###############################################################################

clear 2>/dev/null || true

cat <<EOF

============================================================
        $SCRIPT_NAME
============================================================

 OS           : $OS_NAME
 Release      : $OS_RELEASE
 Architecture : $ARCH

============================================================

EOF

###############################################################################
# Detect target user
###############################################################################

TARGET_USER="${SUDO_USER:-}"

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    TARGET_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)"
fi

if [ -z "$TARGET_USER" ]; then
    warn "Could not automatically detect normal user."
    printf "Enter XFCE username: "
    read TARGET_USER
fi

id "$TARGET_USER" >/dev/null 2>&1 ||
    die "User '$TARGET_USER' does not exist."

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

[ -n "$TARGET_HOME" ] ||
    die "Could not determine home directory for $TARGET_USER."

log "XFCE user : $TARGET_USER"
log "Home       : $TARGET_HOME"

###############################################################################
# Check network
###############################################################################

log "Checking network connectivity..."

if ftp -o /dev/null https://cdn.openbsd.org/ >/dev/null 2>&1; then
    ok "Network connectivity available."
else
    warn "Could not reach cdn.openbsd.org."
    warn "Package installation may fail."
fi

###############################################################################
# Package database sanity check
###############################################################################

log "Checking package database..."

if command -v pkg_check >/dev/null 2>&1; then

    if pkg_check -n >/dev/null 2>&1; then
        ok "Package database looks healthy."
    else
        warn "pkg_check reported possible package database problems."
        warn "Running safe package database check..."

        pkg_check -n || true
    fi

else
    warn "pkg_check not found."
fi

###############################################################################
# Backup directory
###############################################################################

BACKUP_DIR="/root/xfce-installer-backup"

mkdir -p "$BACKUP_DIR" || die "Cannot create $BACKUP_DIR"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

###############################################################################
# Backup helper
###############################################################################

backup_file() {
    FILE="$1"

    if [ -f "$FILE" ]; then

        DEST="$BACKUP_DIR/$(basename "$FILE").$TIMESTAMP"

        cp -p "$FILE" "$DEST" || {
            warn "Could not backup $FILE"
            return 1
        }

        log "Backup created: $DEST"
    fi
}

###############################################################################
# Package helpers
###############################################################################

is_package_installed() {
    PKG="$1"

    pkg_info -e "$PKG" >/dev/null 2>&1
}

cleanup_partial_package() {

    PKG="$1"

    PARTIAL="$(pkg_info -q | grep '^partial-' | grep "$PKG" || true)"

    if [ -n "$PARTIAL" ]; then

        warn "Detected partial package related to: $PKG"

        for P in $PARTIAL; do
            log "Removing partial package: $P"
            pkg_delete -a -v "$P" >/dev/null 2>&1 || true
        done
    fi
}

install_package() {

    PKG="$1"
    REQUIRED="$2"

    if is_package_installed "$PKG"; then
        ok "$PKG already installed."
        return 0
    fi

    log "Installing: $PKG"

    if pkg_add "$PKG"; then
        ok "$PKG installed."
        return 0
    fi

    warn "Initial installation failed: $PKG"

    ###########################################################################
    # Cleanup partial package
    ###########################################################################

    cleanup_partial_package "$PKG"

    ###########################################################################
    # Retry
    ###########################################################################

    log "Retrying installation: $PKG"

    if pkg_add "$PKG"; then
        ok "$PKG installed on retry."
        return 0
    fi

    ###########################################################################
    # Final result
    ###########################################################################

    if [ "$REQUIRED" = "yes" ]; then
        error "Required package failed: $PKG"
        return 1
    fi

    warn "Optional package failed: $PKG"
    return 0
}

###############################################################################
# Mandatory packages
###############################################################################

cat <<EOF

============================================================
 Installing XFCE
============================================================

EOF

MANDATORY_PACKAGES="
xfce
dbus
fontconfig
"

FAILED_REQUIRED=0

for PKG in $MANDATORY_PACKAGES; do
    if ! install_package "$PKG" yes; then
        FAILED_REQUIRED=1
    fi
done

if [ "$FAILED_REQUIRED" -ne 0 ]; then

    error "One or more mandatory packages failed."

    echo
    echo "Running package consistency check..."
    pkg_check -n || true

    die "XFCE installation cannot continue."
fi

###############################################################################
# Optional packages
###############################################################################

cat <<EOF

============================================================
 Installing optional XFCE packages
============================================================

EOF

OPTIONAL_PACKAGES="
thunar
xfce4-terminal
mousepad
"

for PKG in $OPTIONAL_PACKAGES; do
    install_package "$PKG" no || true
done

###############################################################################
# Optional Mozilla dictionaries
#
# NOT required for XFCE.
###############################################################################

cat <<EOF

============================================================
 Optional Mozilla dictionary
============================================================

EOF

if install_package "mozilla-dicts-ca" no; then
    ok "Optional Mozilla dictionary stage completed."
else
    warn "Mozilla dictionary unavailable; continuing."
fi

###############################################################################
# Package consistency check
###############################################################################

echo
log "Running final package consistency check..."

if pkg_check -n >/dev/null 2>&1; then
    ok "Package database check passed."
else
    warn "pkg_check reported warnings."
    warn "This does not necessarily mean XFCE is unusable."
fi

###############################################################################
# PATH
###############################################################################

cat <<EOF

============================================================
 Configuring PATH
============================================================

EOF

PATH_LINE='export PATH="/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin:$PATH"'

USER_PROFILE="$TARGET_HOME/.profile"

if [ -f "$USER_PROFILE" ]; then
    backup_file "$USER_PROFILE"
fi

if ! grep -F "$PATH_LINE" "$USER_PROFILE" >/dev/null 2>&1; then

    printf '\n# OpenBSD XFCE\n%s\n' "$PATH_LINE" >> "$USER_PROFILE"

    ok "XFCE PATH added to .profile."

else
    ok "XFCE PATH already configured."
fi

###############################################################################
# .xsession
###############################################################################

cat <<EOF

============================================================
 Configuring .xsession
============================================================

EOF

XSESSION="$TARGET_HOME/.xsession"

if [ -f "$XSESSION" ]; then
    backup_file "$XSESSION"
fi

cat > "$XSESSION" <<'EOF'
#!/bin/sh

# OpenBSD XFCE session

export PATH="/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin:$PATH"

# XDG environment
export XDG_CURRENT_DESKTOP="XFCE"
export XDG_SESSION_DESKTOP="xfce"

# Start D-Bus session if available
if command -v dbus-launch >/dev/null 2>&1; then
    exec dbus-launch --exit-with-session startxfce4
else
    exec startxfce4
fi
EOF

chmod 755 "$XSESSION"

ok ".xsession configured."

###############################################################################
# Fix ownership
###############################################################################

chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$USER_PROFILE" 2>/dev/null || true
chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$XSESSION"

###############################################################################
# Xenodm
###############################################################################

cat <<EOF

============================================================
 Configuring Xenodm
============================================================

EOF

XENODM="/usr/X11R6/bin/xenodm"

if [ -x "$XENODM" ]; then
    ok "Xenodm found: $XENODM"

    backup_file "/etc/rc.conf.local"

    rcctl enable xenodm

    ok "Xenodm enabled."
else
    die "Xenodm not found: $XENODM"
fi

###############################################################################
# D-Bus / messagebus
###############################################################################

cat <<EOF

============================================================
 Configuring D-Bus
============================================================

EOF

MESSAGEBUS_RC="/etc/rc.d/messagebus"

if [ -x "$MESSAGEBUS_RC" ]; then

    ok "messagebus rc.d script found."

    rcctl enable messagebus

    ok "messagebus enabled."

else

    warn "messagebus rc.d script not found."

    if [ -x /usr/local/bin/dbus-daemon ]; then
        warn "dbus-daemon exists, but messagebus rc script is missing."
    fi

fi

###############################################################################
# XFCE executable verification
###############################################################################

cat <<EOF

============================================================
 XFCE Verification
============================================================

EOF

verify_binary() {

    NAME="$1"

    if command -v "$NAME" >/dev/null 2>&1; then
        BIN="$(command -v "$NAME")"
        ok "$NAME -> $BIN"
    else
        warn "$NAME not found."
    fi
}

verify_binary startxfce4
verify_binary xfce4-session
verify_binary xfce4-panel
verify_binary xfwm4
verify_binary thunar
verify_binary xfce4-terminal
verify_binary mousepad
verify_binary dbus-launch

###############################################################################
# Xenodm verification
###############################################################################

if [ -x /usr/X11R6/bin/xenodm ]; then
    ok "xenodm -> /usr/X11R6/bin/xenodm"
else
    warn "xenodm executable missing."
fi

###############################################################################
# VM detection
###############################################################################

cat <<EOF

============================================================
 Virtual Machine Detection
============================================================

EOF

VM_INFO=""

if command -v sysctl >/dev/null 2>&1; then

    VM_INFO="$(sysctl -n hw.product 2>/dev/null || true)"

fi

case "$VM_INFO" in

    *VirtualBox*)
        ok "VirtualBox detected."
        ;;

    *VMware*)
        ok "VMware detected."
        ;;

    *QEMU*)
        ok "QEMU detected."
        ;;

    *KVM*)
        ok "KVM detected."
        ;;

    *)
        log "Virtual machine type could not be determined."
        ;;
esac

###############################################################################
# Disk / RAM information
###############################################################################

cat <<EOF

============================================================
 System Information
============================================================

EOF

echo "Hostname       : $(hostname)"
echo "OS             : $(uname -s)"
echo "Release        : $(uname -r)"
echo "Architecture   : $(machine -a)"

if command -v sysctl >/dev/null 2>&1; then

    echo "CPU            : $(sysctl -n hw.model 2>/dev/null || echo unknown)"
    echo "CPU cores      : $(sysctl -n hw.ncpu 2>/dev/null || echo unknown)"
    echo "Memory         : $(sysctl -n hw.physmem 2>/dev/null || echo unknown)"

fi

###############################################################################
# Final package list
###############################################################################

cat <<EOF

============================================================
 Installed XFCE Related Packages
============================================================

EOF

pkg_info | grep -Ei '^(xfce|xfwm|xfconf|thunar|dbus|fontconfig|mousepad)' || true

###############################################################################
# Permissions
###############################################################################

chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$TARGET_HOME/.config" \
    2>/dev/null || true

###############################################################################
# Final summary
###############################################################################

cat <<EOF

============================================================
                 INSTALLATION COMPLETE
============================================================

 OpenBSD      : $OS_RELEASE
 Architecture: $ARCH
 User         : $TARGET_USER
 Home         : $TARGET_HOME

 XFCE:
   [OK] xfce package
   [OK] .xsession
   [OK] PATH configuration
   [OK] Xenodm configuration

 D-Bus:
   messagebus configuration attempted

 Backups:
   $BACKUP_DIR

============================================================

Next step:

    reboot

After reboot you should get the Xenodm login screen.

If XFCE does not start:

    cat ~/.xsession
    tail -100 /var/log/xenodm.log

You can also test manually from a TTY:

    export PATH="/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin:\$PATH"
    startxfce4

============================================================

EOF

ok "$SCRIPT_NAME finished."
