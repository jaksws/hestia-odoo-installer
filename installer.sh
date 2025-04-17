#!/bin/bash
# Hestia-Odoo Ultimate Installer
# Version: 1.0
# Author: Jaksws Team
# License: MIT

# ======================[ Global Config ]======================
set -eo pipefail
trap 'error_handler $? $LINENO' ERR

declare -A CONFIG=(
    [DOMAIN]="jaksws.com"
    [SERVER_IP]="129.151.138.90"
    [HESTIA_PORT]="2083"
    [ODOO_VERSION]="18.0"
    [ODOO_PORT]="8069"
    [CF_API]="" # سيتم تعبئته لاحقا
    [CF_EMAIL]="" # سيتم تعبئته لاحقا
    [CF_ZONE]="" # سيتم تعبئته لاحقا
    [BACKUP_DIR]="/backup"
    [LOG_DIR]="/var/log/hestia_installer"
    [MOTD_FILE]="/etc/update-motd.d/99-hestia-instructions"
)

# ======================[ Core Functions ]======================
function init() {
    check_root
    check_internet
    load_config
    setup_directories
    parse_arguments "$@"
}

function check_root() {
    [[ $EUID -ne 0 ]] && {
        echo -e "\033[1;31mيجب تشغيل السكربت كـ root!\033[0m"
        exit 1
    }
}

function check_internet() {
    if ! curl -Is https://cloudflare.com | grep -q "HTTP/2"; then
        log "ERROR" "لا يوجد اتصال بالإنترنت"
        exit 1
    fi
}

function setup_directories() {
    mkdir -p "${CONFIG[BACKUP_DIR]}" "${CONFIG[LOG_DIR]}"
    chmod 700 "${CONFIG[BACKUP_DIR]}"
}

# ======================[ Installation Modules ]======================
function install_hestia() {
    log "INFO" "جاري تثبيت HestiaCP..."
    wget -q https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
    bash hst-install.sh \
        --interactive no \
        --hostname panel.${CONFIG[DOMAIN]} \
        --email admin@${CONFIG[DOMAIN]} \
        --password "$(generate_password)" \
        --port ${CONFIG[HESTIA_PORT]} \
        --apache no \
        --multiphp yes \
        --mysql yes \
        --postgresql yes \
        --named yes \
        --exim yes \
        --dovecot yes \
        --clamav yes \
        --spamassassin yes \
        --fail2ban yes \
        --lang en \
        --username admin \
        --api yes
}

function install_odoo() {
    log "INFO" "جاري تثبيت Odoo ${CONFIG[ODOO_VERSION]}..."
    useradd -m -d /opt/odoo -U -r -s /bin/bash odoo
    sudo -u odoo git clone https://github.com/odoo/odoo --branch ${CONFIG[ODOO_VERSION]} --depth 1 /opt/odoo/src
    
    # إنشاء البيئة الافتراضية
    sudo -u odoo python3 -m venv /opt/odoo/venv
    sudo -u odoo /opt/odoo/venv/bin/pip install -r /opt/odoo/src/requirements.txt
    
    # تكوين الخدمة
    cat > /etc/systemd/system/odoo.service <<EOF
[Unit]
Description=Odoo
After=postgresql.service

[Service]
User=odoo
Group=odoo
WorkingDirectory=/opt/odoo/src
ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/src/odoo-bin -c /etc/odoo.conf
Restart=always
Environment="PATH=/opt/odoo/venv/bin"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now odoo
}

# ======================[ Cloudflare Integration ]======================
function configure_cloudflare() {
    log "INFO" "جاري تكوين Cloudflare DNS..."
    local records=(
        "A|panel|${CONFIG[SERVER_IP]}|true"
        "A|odoo${CONFIG[ODOO_VERSION]}|${CONFIG[SERVER_IP]}|false"
        "MX|@|panel.${CONFIG[DOMAIN]}|10"
        "TXT|@|v=spf1 a mx ~all"
    )

    for record in "${records[@]}"; do
        IFS='|' read -r type name content proxy <<< "$record"
        [[ $name == "@" ]] && name=${CONFIG[DOMAIN]}
        
        local data="{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":3600"
        [[ $type == "MX" ]] && data+=",\"priority\":10"
        [[ $type == "A" ]] && data+=",\"proxied\":$proxy"
        data+="}"
        
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CONFIG[CF_ZONE]}/dns_records" \
            -H "X-Auth-Email: ${CONFIG[CF_EMAIL]}" \
            -H "X-Auth-Key: ${CONFIG[CF_API]}" \
            -H "Content-Type: application/json" \
            --data "$data"
    done
}

# ======================[ MOTD Configuration ]======================
function setup_motd() {
    log "INFO" "جاري تكوين رسالة الترحيب..."
    cat > ${CONFIG[MOTD_FILE]} <<'EOL'
#!/bin/bash
# Hestia-Odoo Welcome Message

# ألوان ANSI
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
NC='\033[0m'

echo -e "${GREEN}"
cat << "EOF"
   __  ______  _________    ____  _____ 
  / / / / __ \/ ___/__  /   / __ \/ ___/
 / / / / /_/ / / __/_  /   / /_/ / __/  
/_/ /_/\____/_/ /___ /_/   \____/_/     
EOF
echo -e "${NC}"

echo -e "${BLUE}=== تعليمات الاستخدام ===${NC}"
echo -e "${GREEN}التثبيت الكامل:${NC} sudo ./installer.sh --install"
echo -e "${GREEN}إنشاء نسخة احتياطية:${NC} sudo ./installer.sh --backup"
echo -e "${GREEN}استعادة نسخة:${NC} sudo ./installer.sh --restore"
echo -e "${GREEN}التحديث:${NC} sudo ./installer.sh --update"
echo -e "${GREEN}الإزالة:${NC} sudo ./installer.sh --uninstall"

echo -e "\n${BLUE}=== معلومات الاتصال ===${NC}"
echo -e "لوحة التحكم: https://panel.${CONFIG[DOMAIN]}:${CONFIG[HESTIA_PORT]}"
echo -e "الدعم الفني: support@${CONFIG[DOMAIN]}"
EOL

    chmod +x ${CONFIG[MOTD_FILE]}
    chmod -x /etc/update-motd.d/*
    chmod +x ${CONFIG[MOTD_FILE]}
}

# ======================[ Main Execution ]======================
case "$1" in
    --install)
        init "$@"
        install_hestia
        install_odoo
        configure_cloudflare
        setup_motd
        ;;
    --uninstall)
        log "WARN" "جاري إزالة جميع المكونات..."
        systemctl stop odoo
        userdel -r odoo
        rm -rf /opt/odoo
        ;;
    --backup)
        create_backup
        ;;
    --restore)
        restore_backup
        ;;
    --update)
        log "INFO" "جاري تحديث السكربت..."
        wget -q -O "$0" https://raw.githubusercontent.com/user/repo/main/installer.sh
        chmod +x "$0"
        ;;
    *)
        echo "الاستخدام: $0 {--install|--uninstall|--backup|--restore|--update}"
        exit 1
        ;;
esac

log "SUCCESS" "تم تنفيذ العملية بنجاح!"
exit 0
