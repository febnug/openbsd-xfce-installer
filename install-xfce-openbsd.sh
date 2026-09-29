#!/bin/ksh

#
# ============================================================
# OpenBSD XFCE Auto Installer
# Supports:
#   - OpenBSD 7.8
#   - OpenBSD 7.9
#
# Desktop:
#   - XFCE
#   - Xenodm
#   - D-Bus
#   - Firefox
#   - Thunar
#   - XFCE Terminal
#   - Mousepad
#
# Features:
#   - Automatic OpenBSD version detection
#   - Automatic architecture detection
#   - packages-stable repository
#   - VirtualBox / QEMU / VMware detection
#   - Configuration backup
#   - Idempotent package installation
#   - XFCE .xsession setup
#   - Xenodm enablement
#
# Usage:
#
#   chmod +x install-xfce-openbsd.sh
#
#   doas ./install-xfce-openbsd.sh
#
# Or:
#
#   doas ./install-xfce-openbsd.sh username
#
# ============================================================

set -e

SCRIPT_NAME="OpenBSD XFCE Auto Installer"
SCRIPT_VERSION="2.0"

BACKUP_ROOT="/root/xfce-installer-backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

echo
echo "============================================================"
echo "        ${SCRIPT_NAME}"
echo "============================================================"
echo
echo "Version : ${SCRIPT_VERSION}"
echo

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then

    echo "[ERROR] Script harus dijalankan sebagai root."
    echo
    echo "Gunakan:"
    echo
    echo "    doas $0"
    echo

    exit 1

fi

# ------------------------------------------------------------
# OpenBSD check
# ------------------------------------------------------------

if [ "$(uname -s)" != "OpenBSD" ]; then

    echo "[ERROR] Sistem ini bukan OpenBSD."

    exit 1

fi

# ------------------------------------------------------------
# Detect OS
# ------------------------------------------------------------

OS_VERSION="$(uname -r)"
ARCH="$(machine -a)"

echo "[INFO] Operating System : OpenBSD ${OS_VERSION}"
echo "[INFO] Architecture    : ${ARCH}"
echo

# ------------------------------------------------------------
# Supported versions
# ------------------------------------------------------------

case "${OS_VERSION}" in

    7.8)
        echo "[OK] OpenBSD 7.8 supported."
        ;;

    7.9)
        echo "[OK] OpenBSD 7.9 supported."
        ;;

    *)
        echo "[ERROR] OpenBSD ${OS_VERSION} belum didukung."
        echo
        echo "Supported versions:"
        echo "  - OpenBSD 7.8"
        echo "  - OpenBSD 7.9"
        echo
        exit 1
        ;;

esac

# ------------------------------------------------------------
# Detect machine
# ------------------------------------------------------------

echo "============================================================"
echo " Detecting machine"
echo "============================================================"
echo

VM_TYPE="physical"

if [ -r /var/run/dmesg.boot ]; then

    if grep -qi "VirtualBox" /var/run/dmesg.boot; then

        VM_TYPE="virtualbox"

    elif grep -qiE "QEMU|VirtIO|KVM" /var/run/dmesg.boot; then

        VM_TYPE="qemu"

    elif grep -qiE "VMware|vmx" /var/run/dmesg.boot; then

        VM_TYPE="vmware"

    fi

fi

echo "[INFO] Machine type: ${VM_TYPE}"
echo

# ------------------------------------------------------------
# Package repository
# ------------------------------------------------------------

PKG_REPOSITORY="https://cdn.openbsd.org/pub/OpenBSD/${OS_VERSION}/packages-stable/${ARCH}/"

export PKG_PATH="${PKG_REPOSITORY}"

echo "============================================================"
echo " Package repository"
echo "============================================================"
echo
echo "${PKG_PATH}"
echo

# ------------------------------------------------------------
# Target user
# ------------------------------------------------------------

TARGET_USER=""

if [ -n "${1:-}" ]; then

    TARGET_USER="$1"

elif [ -n "${DOAS_USER:-}" ]; then

    TARGET_USER="${DOAS_USER}"

elif [ -n "${SUDO_USER:-}" ]; then

    TARGET_USER="${SUDO_USER}"

fi

if [ -z "${TARGET_USER}" ]; then

    echo "============================================================"
    echo " XFCE user"
    echo "============================================================"
    echo

    printf "Username yang akan menggunakan XFCE: "
    read TARGET_USER

fi

# ------------------------------------------------------------
# Validate user
# ------------------------------------------------------------

if ! id "${TARGET_USER}" >/dev/null 2>&1; then

    echo
    echo "[ERROR] User '${TARGET_USER}' tidak ditemukan."
    echo

    exit 1

fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

if [ -z "${TARGET_HOME}" ]; then

    echo "[ERROR] Home directory tidak ditemukan."

    exit 1

fi

echo
echo "[INFO] XFCE user : ${TARGET_USER}"
echo "[INFO] Home      : ${TARGET_HOME}"
echo

# ------------------------------------------------------------
# Backup function
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Create backup
# ------------------------------------------------------------

echo "============================================================"
echo " Creating configuration backup"
echo "============================================================"
echo

mkdir -p "${BACKUP_DIR}"

backup_file "/etc/rc.conf.local"
backup_file "/etc/wsconsctl.conf"
backup_file "${TARGET_HOME}/.xsession"
backup_file "${TARGET_HOME}/.xinitrc"
backup_file "${TARGET_HOME}/.profile"

echo
echo "[OK] Backup:"
echo "     ${BACKUP_DIR}"
echo

# ------------------------------------------------------------
# Package installation helper
# ------------------------------------------------------------

install_package()
{
    PACKAGE="$1"

    echo
    echo "[PACKAGE] ${PACKAGE}"

    if pkg_info -e "${PACKAGE}" >/dev/null 2>&1; then

        echo "[OK] Already installed."

    else

        echo "[INFO] Installing ${PACKAGE}..."

        pkg_add "${PACKAGE}"

    fi
}

# ------------------------------------------------------------
# Install XFCE
# ------------------------------------------------------------

echo "============================================================"
echo " Installing XFCE"
echo "============================================================"
echo

install_package "xfce"
install_package "dbus"

# ------------------------------------------------------------
# Desktop applications
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Installing desktop applications"
echo "============================================================"
echo

install_package "firefox"
install_package "xfce4-terminal"
install_package "thunar"
install_package "mousepad"

# ------------------------------------------------------------
# Fonts
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Installing fonts"
echo "============================================================"
echo

install_package "fontconfig"

# ------------------------------------------------------------
# Verify XFCE
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Verifying XFCE"
echo "============================================================"
echo

FAILED=0

for BIN in \
    startxfce4 \
    xfce4-session \
    xfwm4 \
    xfce4-panel \
    xfce4-terminal \
    thunar
do

    if command -v "${BIN}" >/dev/null 2>&1; then

        echo "[OK] ${BIN}"

    else

        echo "[WARNING] ${BIN} tidak ditemukan."

        FAILED=1

    fi

done

# ------------------------------------------------------------
# D-Bus
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuring D-Bus"
echo "============================================================"
echo

DBUS_SERVICE=""

if [ -f /etc/rc.d/messagebus ]; then

    DBUS_SERVICE="messagebus"

elif [ -f /etc/rc.d/dbus ]; then

    DBUS_SERVICE="dbus"

fi

if [ -n "${DBUS_SERVICE}" ]; then

    echo "[INFO] D-Bus service: ${DBUS_SERVICE}"

    rcctl enable "${DBUS_SERVICE}"

    if rcctl check "${DBUS_SERVICE}" >/dev/null 2>&1; then

        echo "[OK] D-Bus already running."

    else

        echo "[INFO] Starting D-Bus..."

        rcctl start "${DBUS_SERVICE}" || true

    fi

else

    echo "[WARNING] D-Bus rc.d service tidak ditemukan."

fi

# ------------------------------------------------------------
# XFCE session
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuring XFCE session"
echo "============================================================"
echo

XSESSION="${TARGET_HOME}/.xsession"

cat > "${XSESSION}" <<'EOF'
#!/bin/sh

#
# XFCE session for OpenBSD
#

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

if command -v dbus-launch >/dev/null 2>&1; then

    exec dbus-launch --exit-with-session startxfce4

else

    exec startxfce4

fi
EOF

chown "${TARGET_USER}:users" "${XSESSION}"
chmod 700 "${XSESSION}"

echo "[OK] ${XSESSION}"

# ------------------------------------------------------------
# XFCE configuration directory
# ------------------------------------------------------------

mkdir -p "${TARGET_HOME}/.config/xfce4"

chown -R "${TARGET_USER}:users" \
    "${TARGET_HOME}/.config"

# ------------------------------------------------------------
# Xenodm
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuring Xenodm"
echo "============================================================"
echo

if [ -x /usr/sbin/xenodm ]; then

    echo "[OK] xenodm ditemukan."

    rcctl enable xenodm

else

    echo "[ERROR] xenodm tidak ditemukan."

    exit 1

fi

# ------------------------------------------------------------
# rc.conf.local
# ------------------------------------------------------------

RC_LOCAL="/etc/rc.conf.local"

touch "${RC_LOCAL}"

if grep -q '^xenodm_flags=' "${RC_LOCAL}"; then

    echo "[OK] xenodm_flags sudah ada."

else

    echo 'xenodm_flags=""' >> "${RC_LOCAL}"

    echo "[OK] xenodm_flags ditambahkan."

fi

# ------------------------------------------------------------
# Keyboard
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuring keyboard"
echo "============================================================"
echo

WSCONF="/etc/wsconsctl.conf"

touch "${WSCONF}"

if grep -q '^keyboard.encoding=' "${WSCONF}"; then

    echo "[OK] keyboard.encoding sudah ada."

else

    echo 'keyboard.encoding=us' >> "${WSCONF}"

    echo "[OK] Default keyboard: us"

fi

# ------------------------------------------------------------
# VirtualBox information
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Virtual machine configuration"
echo "============================================================"
echo

case "${VM_TYPE}" in

    virtualbox)

        echo "[INFO] VirtualBox detected."
        echo
        echo "Recommended VirtualBox settings:"
        echo
        echo "  RAM              : 4 GB"
        echo "  CPU              : 2"
        echo "  Video Memory     : 128 MB"
        echo "  Graphics         : VMSVGA"
        echo "  Disk             : SATA"
        echo "  Network          : Intel PRO/1000"
        echo
        ;;

    qemu)

        echo "[INFO] QEMU/KVM detected."
        echo
        echo "Recommended settings:"
        echo
        echo "  RAM              : 4 GB"
        echo "  CPU              : 2"
        echo "  Disk             : virtio"
        echo "  Network          : virtio"
        echo
        ;;

    vmware)

        echo "[INFO] VMware detected."
        echo
        ;;

    physical)

        echo "[INFO] Physical machine."
        echo
        ;;

esac

# ------------------------------------------------------------
# Firefox
# ------------------------------------------------------------

echo "============================================================"
echo " Browser"
echo "============================================================"
echo

if command -v firefox >/dev/null 2>&1; then

    echo "[OK] Firefox installed."

else

    echo "[WARNING] Firefox binary tidak ditemukan."

fi

# ------------------------------------------------------------
# Fix ownership
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Fixing permissions"
echo "============================================================"
echo

chown "${TARGET_USER}:users" "${TARGET_HOME}"

if [ -d "${TARGET_HOME}/.config" ]; then

    chown -R "${TARGET_USER}:users" \
        "${TARGET_HOME}/.config"

fi

chown "${TARGET_USER}:users" "${XSESSION}"
chmod 700 "${XSESSION}"

# ------------------------------------------------------------
# Service status
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Service status"
echo "============================================================"
echo

if [ -n "${DBUS_SERVICE}" ]; then

    echo "D-Bus:"
    rcctl check "${DBUS_SERVICE}" || true

fi

echo
echo "Xenodm:"
rcctl check xenodm || true

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo

if [ "${FAILED}" -eq 0 ]; then

    echo "[OK] XFCE components verified."

else

    echo "[WARNING] Ada komponen XFCE yang tidak ditemukan."

fi

echo
echo "OpenBSD:"
echo "  ${OS_VERSION}"

echo
echo "Architecture:"
echo "  ${ARCH}"

echo
echo "Machine:"
echo "  ${VM_TYPE}"

echo
echo "User:"
echo "  ${TARGET_USER}"

echo
echo "Desktop:"
echo "  XFCE"

echo
echo "Display manager:"
echo "  Xenodm"

echo
echo "Backup:"
echo "  ${BACKUP_DIR}"

echo
echo "============================================================"
echo " NEXT STEP"
echo "============================================================"
echo

echo "Reboot:"
echo
echo "    reboot"
echo

echo "Flow setelah reboot:"
echo
echo "    Xenodm"
echo "       ↓"
echo "    Login"
echo "       ↓"
echo "    ~/.xsession"
echo "       ↓"
echo "    XFCE"
echo

echo "Jika XFCE gagal start:"
echo
echo "    cat ~/.xsession"
echo "    cat ~/.xsession-errors"
echo "    tail -100 /var/log/xenodm.log"
echo

echo "Backup konfigurasi:"
echo
echo "    ${BACKUP_DIR}"
echo

echo "============================================================"
