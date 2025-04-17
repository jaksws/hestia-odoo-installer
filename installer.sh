#!/bin/bash
# Hestia-Odoo Interactive Installer
# Version: 1.0
# Author: Jaksws Team

# ألوان ANSI
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
NC='\033[0m' # إعادة الضبط

# التأكد من وجود الدليل المطلوب لتسجيل العمليات
LOG_DIR="/var/log/hestia_installer"
LOG_FILE="$LOG_DIR/install.log"
if [ ! -d "$LOG_DIR" ]; then
    echo -e "${YELLOW}إنشاء دليل السجلات: $LOG_DIR${NC}"
    sudo mkdir -p "$LOG_DIR"
    sudo chmod -R 755 "$LOG_DIR"
fi

# طلب إدخال البيانات الأساسية
clear
echo -e "${GREEN}"
cat << "EOF"
   __  ______  _________    ____  _____ 
  / / / / __ \/ ___/__  /   / __ \/ ___/
 / / / / /_/ / / __/_  /   / /_/ / __/  
/_/ /_/\____/_/ /___ /_/   \____/_/     
EOF
echo -e "${NC}"

# طلب إدخال البيانات الأساسية
read -p "أدخل اسم النطاق الرئيسي (مثال: jaksws.com): " DOMAIN
read -p "أدعنوان IP الخاص بالسيرفر: " SERVER_IP
read -p "أدخل منفذ هيستيا (الافتراضي 2083): " HESTIA_PORT
HESTIA_PORT=${HESTIA_PORT:-2083}

read -p "أدخل إصدار Odoo المطلوب (مثال: 18.0): " ODOO_VERSION
read -p "أدخل منفذ Odoo (الافتراضي 8069): " ODOO_PORT
ODOO_PORT=${ODOO_PORT:-8069}

# طلب بيانات Cloudflare
echo -e "${YELLOW}\nإعدادات Cloudflare (اتركها فارغة لتخطي الإعداد):${NC}"
read -p "API Key: " CF_API
read -p "Email: " CF_EMAIL
read -p "Zone ID: " CF_ZONE

# تأكيد الإعدادات
echo -e "${GREEN}\n=== تأكيد الإعدادات ==="
echo -e "النطاق: ${DOMAIN}"
echo -e "IP السيرفر: ${SERVER_IP}"
echo -e "منفذ هيستيا: ${HESTIA_PORT}"
echo -e "إصدار Odoo: ${ODOO_VERSION}"
echo -e "منفذ Odoo: ${ODOO_PORT}"
echo -e "Cloudflare API: ${CF_API:+تم الإدخال}${NC}"

read -p "هل تريد المتابعة؟ (y/n): " CONFIRM
[[ $CONFIRM != [yY] ]] && exit

# وظيفة تثبيت هيستيا
install_hestia() {
    echo -e "${BLUE}\nجاري تثبيت HestiaCP...${NC}" | tee -a "$LOG_FILE"
    wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
    bash hst-install.sh \
        --interactive no \
        --hostname panel.${DOMAIN} \
        --email admin@${DOMAIN} \
        --password "$(openssl rand -base64 12)" \
        --port ${HESTIA_PORT} \
        --apache no \
        --multiphp yes \
        --mysql yes \
        --postgresql yes \
        --named yes \
        --exim yes \
        --dovecot yes \
        --clamav yes \
        --spamassassin yes \
        --fail2ban yes
}

# وظيفة تثبيت Odoo
install_odoo() {
    echo -e "${BLUE}\nجاري تثبيت Odoo...${NC}" | tee -a "$LOG_FILE"
    useradd -m -d /opt/odoo -U -r -s /bin/bash odoo
    sudo -u odoo git clone https://github.com/odoo/odoo --branch ${ODOO_VERSION} --depth 1 /opt/odoo/src
    
    sudo -u odoo python3 -m venv /opt/odoo/venv
    sudo -u odoo /opt/odoo/venv/bin/pip install -r /opt/odoo/src/requirements.txt
    
    cat > /etc/systemd/system/odoo.service <<EOF
[Unit]
Description=Odoo
After=postgresql.service

[Service]
User=odoo
Group=odoo
WorkingDirectory=/opt/odoo/src
ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/src/odoo-bin
Restart=always
Environment="PATH=/opt/odoo/venv/bin"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now odoo
}

# وظيفة إعداد Cloudflare
setup_cloudflare() {
    if [[ -n $CF_API ]]; then
        echo -e "${BLUE}\nجاري إعداد Cloudflare DNS...${NC}" | tee -a "$LOG_FILE"
        curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE}/dns_records" \
            -H "X-Auth-Email: ${CF_EMAIL}" \
            -H "X-Auth-Key: ${CF_API}" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'${DOMAIN}'","content":"'${SERVER_IP}'","ttl":120,"proxied":false}' \
            | tee -a "$LOG_FILE"
    fi
}

# وظيفة إضافة Odoo إلى قائمة التطبيقات السريعة في هيستيا
add_odoo_to_hestia_quick_app() {
    echo -e "${BLUE}\nإضافة Odoo إلى قائمة التطبيقات السريعة في هيستيا...${NC}" | tee -a "$LOG_FILE"
    APP_DIR="/usr/local/hestia/data/templates/web"
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}دليل التطبيقات السريعة غير موجود: $APP_DIR${NC}" | tee -a "$LOG_FILE"
        return 1
    fi

    cat > "$APP_DIR/odoo.tpl" <<EOF
# Odoo Quick App Template
server {
    listen      80;
    server_name ${DOMAIN};
    root        /opt/odoo/src;
    index       index.html;

    location / {
        proxy_pass http://127.0.0.1:${ODOO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    echo -e "${GREEN}تمت إضافة Odoo إلى قائمة التطبيقات السريعة بنجاح.${NC}" | tee -a "$LOG_FILE"
}

# التحقق من صحة الإدخالات
validate_inputs() {
    local valid=true

    if [[ -z "$DOMAIN" || ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}اسم النطاق غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -z "$SERVER_IP" || ! "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${RED}عنوان IP غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -z "$HESTIA_PORT" || ! "$HESTIA_PORT" =~ ^[0-9]{1,5}$ || "$HESTIA_PORT" -lt 1 || "$HESTIA_PORT" -gt 65535 ]]; then
        echo -e "${RED}منفذ هيستيا غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -z "$ODOO_VERSION" || ! "$ODOO_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}إصدار Odoo غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -z "$ODOO_PORT" || ! "$ODOO_PORT" =~ ^[0-9]{1,5}$ || "$ODOO_PORT" -lt 1 || "$ODOO_PORT" -gt 65535 ]]; then
        echo -e "${RED}منفذ Odoo غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -n "$CF_API" && ! "$CF_API" =~ ^[a-zA-Z0-9]{32}$ ]]; then
        echo -e "${RED}مفتاح API الخاص بـ Cloudflare غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -n "$CF_EMAIL" && ! "$CF_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}البريد الإلكتروني الخاص بـ Cloudflare غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ -n "$CF_ZONE" && ! "$CF_ZONE" =~ ^[a-zA-Z0-9]{32}$ ]]; then
        echo -e "${RED}معرف المنطقة الخاص بـ Cloudflare غير صالح.${NC}" | tee -a "$LOG_FILE"
        valid=false
    fi

    if [[ "$valid" = false ]]; then
        echo -e "${RED}يرجى تصحيح الإدخالات غير الصالحة والمحاولة مرة أخرى.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# التحقق من صحة الإدخالات
validate_inputs

# تثبيت هيستيا
install_hestia

# تثبيت Odoo
install_odoo

# إعداد Cloudflare
setup_cloudflare

# إضافة Odoo إلى قائمة التطبيقات السريعة في هيستيا
add_odoo_to_hestia_quick_app

echo -e "${GREEN}\nتم التثبيت بنجاح!${NC}" | tee -a "$LOG_FILE"
