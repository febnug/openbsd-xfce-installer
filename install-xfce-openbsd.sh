#!/bin/ksh

#
# ============================================================
# OpenBSD XFCE Automatic Installer
# ============================================================
#
# Tested target:
#   OpenBSD 7.8
#   OpenBSD 7.9
#
# Architectures:
#   i386
#   amd64
#
# Installs:
#   XFCE
#   D-Bus
#   Firefox
#   Thunar
#   XFCE Terminal
#   Mousepad
#
# Configures:
#   Xenodm
#   .xsession
#   PATH
#   D-Bus session
#
# Does NOT:
#   pkg_add -u
#   modify /etc/rc
#   overwrite existing .xsession without backup
#
# Usage:
#
#   chmod +x install-xfce-openbsd.sh
#   doas ./install-xfce-openbsd.sh
#
# Or:
#
#   doas ./install-xfce-openbsd.sh febri
#
# ============================================================

set -e

SCRIPT_NAME="OpenBSD XFCE Installer"
SCRIPT_VERSION="3.0"

BACKUP_ROOT="/root/xfce-installer-backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

echo
echo "============================================================"
echo "        ${SCRIPT_NAME} ${SCRIPT_VERSION}"
echo "============================================================"
echo

# ============================================================
# ROOT
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Script harus dijalankan sebagai root."
    echo
    echo "Gunakan:"
    echo "    doas $0"
    exit 1
fi

# ============================================================
# OS
# ============================================================

if [ "$(uname -s)" != "OpenBSD" ]; then
    echo "[ERROR] Sistem ini bukan OpenBSD."
    exit 1
fi

OS_VERSION="$(uname -r)"
ARCH="$(machine -a)"

echo "[INFO] OpenBSD     : ${OS_VERSION}"
echo "[INFO] Architecture: ${ARCH}"
echo

case "${OS_VERSION}" in
    7.8|7.9)
        echo "[OK] OpenBSD ${OS_VERSION} supported."
        ;;
    *)
        echo "[ERROR] OpenBSD ${OS_VERSION} belum didukung."
        echo
        echo "Supported:"
        echo "  7.8"
        echo "  7.9"
        exit 1
        ;;
esac

case "${ARCH}" in
    i386|amd64)
        echo "[OK] Architecture ${ARCH} supported."
        ;;
    *)
        echo "[WARNING] Architecture ${ARCH} belum dites."
        echo
        printf "Continue anyway? [y/N]: "
        read ANSWER

        case "${ANSWER}" in
            y|Y)
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
esac

# ============================================================
# USER DETECTION
# ============================================================

TARGET_USER=""

if [ -n "${1:-}" ]; then
    TARGET_USER="$1"
elif [ -n "${DOAS_USER:-}" ]; then
    TARGET_USER="$DOAS_USER"
elif [ -n "${SUDO_USER:-}" ]; then
    TARGET_USER="$SUDO_USER"
fi

if [ -z "${TARGET_USER}" ]; then

    echo
    echo "============================================================"
    echo " XFCE USER"
    echo "============================================================"
    echo

    printf "Username: "
    read TARGET_USER

fi

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
    echo
    echo "[ERROR] User '${TARGET_USER}' tidak ditemukan."
    exit 1
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

if [ -z "${TARGET_HOME}" ]; then
    echo "[ERROR] Home directory tidak ditemukan."
    exit 1
fi

echo
echo "[INFO] User: ${TARGET_USER}"
echo "[INFO] Home: ${TARGET_HOME}"
echo

# ============================================================
# BACKUP
# ============================================================

echo "============================================================"
echo " Creating backup"
echo "============================================================"
echo

mkdir -p "${BACKUP_DIR}"

backup_file()
{
    FILE="$1"

    if [ -e "${FILE}" ]; then

        DEST="${BACKUP_DIR}${FILE}"

        mkdir -p "$(dirname "${DEST}")"
        cp -Rp "${FILE}" "${DEST}"

        echo "[BACKUP] ${FILE}"

    fi
}

backup_file "/etc/rc.conf.local"
backup_file "/etc/wsconsctl.conf"
backup_file "${TARGET_HOME}/.xsession"
backup_file "${TARGET_HOME}/.xinitrc"
backup_file "${TARGET_HOME}/.profile"

echo
echo "[OK] Backup:"
echo "     ${BACKUP_DIR}"
echo

# ============================================================
# PACKAGE REPOSITORY
# ============================================================

echo "============================================================"
echo " Package configuration"
echo "============================================================"
echo

echo "[INFO] pkg_add akan menggunakan repository OpenBSD."
echo "[INFO] Release : ${OS_VERSION}"
echo "[INFO] Arch    : ${ARCH}"
echo

# Don't force PKG_PATH.
# OpenBSD pkg_add already knows how to resolve the release
# and packages-stable repository.

unset PKG_PATH

# ============================================================
# PACKAGE INSTALLER
# ============================================================

install_package()
{
    PACKAGE="$1"

    echo
    echo "------------------------------------------------------------"
    echo "[PACKAGE] ${PACKAGE}"
    echo "------------------------------------------------------------"

    if pkg_info -e "${PACKAGE}" >/dev/null 2>&1; then

        echo "[OK] ${PACKAGE} already installed."

    else

        echo "[INFO] Installing ${PACKAGE}..."

        pkg_add "${PACKAGE}"

    fi
}

# ============================================================
# XFCE
# ============================================================

echo
echo "============================================================"
echo " Installing XFCE"
echo "============================================================"
echo

install_package "xfce"

# ============================================================
# DBUS
# ============================================================

echo
echo "============================================================"
echo " Installing D-Bus"
echo "============================================================"
echo

install_package "dbus"

# ============================================================
# DESKTOP APPLICATIONS
# ============================================================

echo
echo "============================================================"
echo " Installing desktop applications"
echo "============================================================"
echo

install_package "firefox"
install_package "thunar"
install_package "xfce4-terminal"
install_package "mousepad"

# ============================================================
# FONTCONFIG
# ============================================================

echo
echo "============================================================"
echo " Installing font support"
echo "============================================================"
echo

install_package "fontconfig"

# ============================================================
# PATH
# ============================================================

echo
echo "============================================================"
echo " Configuring PATH"
echo "============================================================"
echo

XSESSION="${TARGET_HOME}/.xsession"

cat > "${XSESSION}" <<'EOF'
#!/bin/sh

#
# OpenBSD XFCE session
#

export PATH="/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin:/bin:/usr/bin:/sbin:/usr/sbin"

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

#
# Start XFCE
#

if command -v dbus-launch >/dev/null 2>&1; then

    exec dbus-launch --exit-with-session startxfce4

else

    exec startxfce4

fi
EOF

chown "${TARGET_USER}:users" "${XSESSION}"
chmod 700 "${XSESSION}"

echo "[OK] ${XSESSION}"

# ============================================================
# XFCE CONFIG DIRECTORY
# ============================================================

mkdir -p "${TARGET_HOME}/.config/xfce4"

chown -R "${TARGET_USER}:users" \
    "${TARGET_HOME}/.config"

# ============================================================
# XENODM
# ============================================================

echo
echo "============================================================"
echo " Configuring Xenodm"
echo "============================================================"
echo

XENODM="/usr/X11R6/bin/xenodm"

if [ -x "${XENODM}" ]; then

    echo "[OK] ${XENODM}"

else

    echo "[ERROR] xenodm tidak ditemukan:"
    echo "        ${XENODM}"
    exit 1

fi

# ============================================================
# ENABLE XENODM
# ============================================================

echo
echo "[INFO] Enabling xenodm..."

rcctl enable xenodm

echo "[OK] xenodm enabled."

# ============================================================
# DBUS SERVICE DETECTION
# ============================================================

echo
echo "============================================================"
echo " Detecting D-Bus service"
echo "============================================================"
echo

DBUS_SERVICE=""

if [ -f /etc/rc.d/messagebus ]; then

    DBUS_SERVICE="messagebus"

elif [ -f /etc/rc.d/dbus ]; then

    DBUS_SERVICE="dbus"

fi

if [ -n "${DBUS_SERVICE}" ]; then

    echo "[OK] D-Bus service: ${DBUS_SERVICE}"

    rcctl enable "${DBUS_SERVICE}"

    if rcctl check "${DBUS_SERVICE}" >/dev/null 2>&1; then

        echo "[OK] D-Bus already running."

    else

        echo "[INFO] Starting D-Bus..."

        rcctl start "${DBUS_SERVICE}" || true

    fi

else

    echo "[INFO] No system D-Bus rc.d service found."
    echo "[INFO] XFCE will use session D-Bus when available."

fi

# ============================================================
# VERIFY XFCE
# ============================================================

echo
echo "============================================================"
echo " Verifying XFCE"
echo "============================================================"
echo

FAILED=0

verify_binary()
{
    BIN="$1"

    if command -v "${BIN}" >/dev/null 2>&1; then

        echo "[OK] ${BIN}"
        echo "     $(command -v "${BIN}")"

    else

        echo "[WARNING] ${BIN} tidak ditemukan."

        FAILED=1

    fi
}

verify_binary "startxfce4"
verify_binary "xfce4-session"
verify_binary "xfwm4"
verify_binary "xfce4-panel"
verify_binary "xfce4-terminal"
verify_binary "thunar"

# ============================================================
# VERIFY FIREFOX
# ============================================================

echo
echo "============================================================"
echo " Verifying applications"
echo "============================================================"
echo

verify_binary "firefox"
verify_binary "mousepad"

# ============================================================
# VERIFY XENODM
# ============================================================

echo
echo "============================================================"
echo " Verifying Xenodm"
echo "============================================================"
echo

if [ -x "/usr/X11R6/bin/xenodm" ]; then
    echo "[OK] /usr/X11R6/bin/xenodm"
else
    echo "[ERROR] xenodm tidak ditemukan."
    FAILED=1
fi

# ============================================================
# MACHINE DETECTION
# ============================================================

echo
echo "============================================================"
echo " Detecting virtual machine"
echo "============================================================"
echo

VM_TYPE="physical"

if [ -r /var/run/dmesg.boot ]; then

    if grep -qi "VirtualBox" /var/run/dmesg.boot; then

        VM_TYPE="virtualbox"

    elif grep -qiE "QEMU|KVM|VirtIO" /var/run/dmesg.boot; then

        VM_TYPE="qemu"

    elif grep -qiE "VMware|vmx" /var/run/dmesg.boot; then

        VM_TYPE="vmware"

    fi

fi

echo "[INFO] Machine type: ${VM_TYPE}"

case "${VM_TYPE}" in

    virtualbox)

        echo
        echo "VirtualBox recommendation:"
        echo
        echo "  RAM           : 2-4 GB"
        echo "  CPU           : 2"
        echo "  Video Memory  : 128 MB"
        echo "  Graphics      : VMSVGA"
        echo "  Network       : Intel PRO/1000"
        echo
        ;;

    qemu)

        echo
        echo "QEMU/KVM recommendation:"
        echo
        echo "  RAM           : 2-4 GB"
        echo "  CPU           : 2"
        echo "  Disk          : virtio"
        echo "  Network       : virtio"
        echo
        ;;

    vmware)

        echo
        echo "VMware detected."
        echo
        ;;

    physical)

        echo
        echo "Physical machine detected."
        echo
        ;;

esac

# ============================================================
# FIX PERMISSIONS
# ============================================================

echo
echo "============================================================"
echo " Fixing permissions"
echo "============================================================"
echo

chown "${TARGET_USER}:users" "${TARGET_HOME}"

chown "${TARGET_USER}:users" "${XSESSION}"

chmod 700 "${XSESSION}"

if [ -d "${TARGET_HOME}/.config" ]; then

    chown -R "${TARGET_USER}:users" \
        "${TARGET_HOME}/.config"

fi

echo "[OK] Permissions fixed."

# ============================================================
# SERVICE STATUS
# ============================================================

echo
echo "============================================================"
echo " Service status"
echo "============================================================"
echo

echo "Xenodm:"
rcctl check xenodm || true

if [ -n "${DBUS_SERVICE}" ]; then

    echo
    echo "D-Bus:"
    rcctl check "${DBUS_SERVICE}" || true

fi

# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "             XFCE INSTALLATION COMPLETE"
echo "============================================================"
echo

echo "OpenBSD      : ${OS_VERSION}"
echo "Architecture : ${ARCH}"
echo "Machine      : ${VM_TYPE}"
echo "User         : ${TARGET_USER}"
echo "Home         : ${TARGET_HOME}"
echo
echo "Desktop      : XFCE"
echo "Display      : Xenodm"
echo
echo "Backup       : ${BACKUP_DIR}"
echo

if [ "${FAILED}" -eq 0 ]; then

    echo "[OK] Semua komponen utama berhasil diverifikasi."

else

    echo "[WARNING] Ada komponen yang belum berhasil diverifikasi."

fi

echo
echo "============================================================"
echo " NEXT STEP"
echo "============================================================"
echo

echo "Reboot dengan:"
echo
echo "    reboot"
echo

echo "Setelah reboot:"
echo
echo "    Xenodm"
echo "       ↓"
echo "    Login"
echo "       ↓"
echo "    ~/.xsession"
echo "       ↓"
echo "    startxfce4"
echo "       ↓"
echo "    XFCE"
echo

echo "Jika XFCE bermasalah:"
echo
echo "    cat ~/.xsession"
echo "    cat ~/.xsession-errors"
echo "    tail -100 /var/log/xenodm.log"
echo

echo "Backup:"
echo
echo "    ${BACKUP_DIR}"
echo

echo "============================================================"
