#!/bin/bash
# Hestia-Odoo Interactive Installer
# Version: 2.0
# Author: Jaksws Team

# ألوان ANSI
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
NC='\033[0m' # إعادة الضبط

# إعدادات السجل
LOG_DIR="/var/log/hestia_installer"
LOG_FILE="$LOG_DIR/install.log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# واجهة المستخدم
clear
echo -e "${GREEN}"
cat << "EOF"
   __  ______  _________    ____  _____ 
  / / / / __ \/ ___/__  /   / __ \/ ___/
 / / / / /_/ / / __/_  /   / /_/ / __/  
/_/ /_/\____/_/ /___ /_/   \____/_/     
EOF
echo -e "${NC}"

# طلب المدخلات
read -p "أدخل اسم النطاق الرئيسي (مثال: jaksws.com): " DOMAIN
read -p "أدخل عنوان IP الخاص بالسيرفر: " SERVER_IP
read -p "أدخل منفذ هيستيا (الافتراضي 2083): " HESTIA_PORT
HESTIA_PORT=${HESTIA_PORT:-2083}

read -p "أدخل إصدار Odoo المطلوب (مثال: 18.0): " ODOO_VERSION
read -p "أدخل منفذ Odoo (الافتراضي 8069): " ODOO_PORT
ODOO_PORT=${ODOO_PORT:-8069}

# إعدادات Cloudflare
echo -e "${YELLOW}\nإعدادات Cloudflare (اتركها فارغة لتخطي الإعداد):${NC}"
read -p "اختر طريقة المصادقة (1 للـ API Token، 2 للـ API Key): " CF_AUTH_METHOD

case $CF_AUTH_METHOD in
    1)
        read -p "API Token: " CF_TOKEN
        ;;
    2)
        read -p "API Key: " CF_API_KEY
        read -p "Email: " CF_EMAIL
        ;;
    *)
        echo -e "${YELLOW}سيتم تخطي إعداد Cloudflare.${NC}"
        ;;
esac

[[ -n $CF_AUTH_METHOD ]] && read -p "Zone ID: " CF_ZONE

# تأكيد الإعدادات
echo -e "${GREEN}\n=== تأكيد الإعدادات ==="
echo -e "النطاق: ${DOMAIN}"
echo -e "IP السيرفر: ${SERVER_IP}"
echo -e "منفذ هيستيا: ${HESTIA_PORT}"
echo -e "إصدار Odoo: ${ODOO_VERSION}"
echo -e "منفذ Odoo: ${ODOO_PORT}"
[[ -n $CF_AUTH_METHOD ]] && echo -e "طريقة مصادقة Cloudflare: $([ "$CF_AUTH_METHOD" == "1" ] && echo "Token" || echo "API Key")"
echo -e "${NC}"

read -p "هل تريد المتابعة؟ (y/n): " CONFIRM
[[ $CONFIRM != [yY] ]] && exit

# التحقق من الصحة
validate_inputs() {
    local valid=true

    # التحقق من النطاق
    [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && {
        echo -e "${RED}خطأ: اسم النطاق غير صالح${NC}" | tee -a "$LOG_FILE"
        valid=false
    }

    # التحقق من IP
    [[ ! "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
        echo -e "${RED}خطأ: عنوان IP غير صالح${NC}" | tee -a "$LOG_FILE"
        valid=false
    }

    # التحقق من Cloudflare
    if [[ -n $CF_AUTH_METHOD ]]; then
        if [[ $CF_AUTH_METHOD == "1" && (${#CF_TOKEN} -ne 40 || -z "$CF_TOKEN") ]]; then
            echo -e "${RED}خطأ: التوكن يجب أن يكون 40 حرفًا${NC}" | tee -a "$LOG_FILE"
            valid=false
        elif [[ $CF_AUTH_METHOD == "2" && (${#CF_API_KEY} -ne 37 || -z "$CF_EMAIL") ]]; then
            echo -e "${RED}خطأ: بيانات Cloudflare غير صالحة${NC}" | tee -a "$LOG_FILE"
            valid=false
        fi
        
        [[ ! "$CF_ZONE" =~ ^[a-zA-Z0-9]{32}$ ]] && {
            echo -e "${RED}خطأ: Zone ID غير صالح${NC}" | tee -a "$LOG_FILE"
            valid=false
        }
    fi

    $valid || exit 1
}

# تثبيت HestiaCP
install_hestia() {
    echo -e "${BLUE}\nجاري تثبيت HestiaCP...${NC}" | tee -a "$LOG_FILE"
    wget -q https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
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

# تثبيت Odoo
install_odoo() {
    echo -e "${BLUE}\nجاري تثبيت Odoo...${NC}" | tee -a "$LOG_FILE"
    useradd -m -d /opt/odoo -U -r -s /bin/bash odoo
    sudo -u odoo git clone -b ${ODOO_VERSION} --depth 1 https://github.com/odoo/odoo /opt/odoo/src
    
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

# إعداد Cloudflare
setup_cloudflare() {
    [[ -z $CF_AUTH_METHOD ]] && return

    echo -e "${BLUE}\nجاري إعداد Cloudflare DNS...${NC}" | tee -a "$LOG_FILE"
    
    # تحديد رؤوس المصادقة
    if [[ $CF_AUTH_METHOD == "1" ]]; then
        AUTH_HEADER="Authorization: Bearer $CF_TOKEN"
    else
        AUTH_HEADER="X-Auth-Email: $CF_EMAIL\nX-Auth-Key: $CF_API_KEY"
    fi

    # السجلات المطلوبة
    declare -A records=(
        ["panel"]="A"
        ["odoo${ODOO_VERSION}"]="A"
        ["@"]="MX"
        ["@"]="TXT"
    )

    for record in "${!records[@]}"; do
        type=${records[$record]}
        case $type in
            "A")
                content=$SERVER_IP
                proxied=$([[ "$record" == "panel" ]] && echo "true" || echo "false")
                data=$(jq -n \
                    --arg type "$type" \
                    --arg name "$record" \
                    --arg content "$content" \
                    --argjson ttl 3600 \
                    --argjson proxied $proxied \
                    '{"type":$type,"name":$name,"content":$content,"ttl":$ttl,"proxied":$proxied}')
                ;;
            "MX")
                content="mail.$DOMAIN"
                data=$(jq -n \
                    --arg type "$type" \
                    --arg name "@" \
                    --arg content "$content" \
                    --argjson priority 10 \
                    --argjson ttl 3600 \
                    '{"type":$type,"name":$name,"content":$content,"priority":$priority,"ttl":$ttl}')
                ;;
            "TXT")
                content="v=spf1 a mx ~all"
                data=$(jq -n \
                    --arg type "$type" \
                    --arg name "@" \
                    --arg content "$content" \
                    --argjson ttl 3600 \
                    '{"type":$type,"name":$name,"content":$content,"ttl":$ttl}')
                ;;
        esac

        echo -e "${BLUE}إضافة سجل $type لـ $record...${NC}" | tee -a "$LOG_FILE"
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE}/dns_records" \
            -H "$AUTH_HEADER" \
            -H "Content-Type: application/json" \
            --data "$data")

        if echo "$response" | grep -q '"success": true'; then
            echo -e "${GREEN}تمت الإضافة بنجاح!${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${RED}فشل الإضافة: $response${NC}" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

# إضافة Odoo إلى قائمة التطبيقات السريعة في هيستيا
add_odoo_to_hestia_quick_app() {
    echo -e "${BLUE}\nإضافة Odoo إلى قائمة التطبيقات السريعة في هيستيا...${NC}" | tee -a "$LOG_FILE"
    cat > /usr/local/hestia/data/templates/web/odoo.tpl <<EOF
server {
    listen      80;
    server_name odoo.${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:${ODOO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    cat > /usr/local/hestia/data/templates/web/odoo.stpl <<EOF
server {
    listen      443 ssl;
    server_name odoo.${DOMAIN};
    ssl_certificate      /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key  /etc/ssl/private/ssl-cert-snakeoil.key;
    location / {
        proxy_pass http://127.0.0.1:${ODOO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    echo -e "${GREEN}تمت الإضافة بنجاح!${NC}" | tee -a "$LOG_FILE"
}

# الإعداد النهائي
final_setup() {
    echo -e "${GREEN}\n=== الإعداد النهائي ==="
    echo -e "لوحة التحكم: https://panel.${DOMAIN}:${HESTIA_PORT}"
    echo -e "منفذ Odoo: ${ODOO_PORT}"
    echo -e "تم التثبيت بنجاح!${NC}"
}

# اكتشاف البيئة وتطبيق أفضل الإعدادات
detect_environment() {
    echo -e "${BLUE}\nاكتشاف البيئة وتطبيق أفضل الإعدادات...${NC}" | tee -a "$LOG_FILE"
    # اكتشاف نظام التشغيل
    OS=$(uname -s)
    case $OS in
        Linux)
            DISTRO=$(lsb_release -is)
            VERSION=$(lsb_release -rs)
            echo -e "${GREEN}نظام التشغيل: $DISTRO $VERSION${NC}" | tee -a "$LOG_FILE"
            ;;
        Darwin)
            echo -e "${GREEN}نظام التشغيل: macOS${NC}" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "${RED}نظام التشغيل غير مدعوم${NC}" | tee -a "$LOG_FILE"
            exit 1
            ;;
    esac

    # تطبيق الإعدادات المخصصة بناءً على البيئة
    if [[ $DISTRO == "Ubuntu" ]]; then
        echo -e "${BLUE}تطبيق إعدادات مخصصة لـ Ubuntu...${NC}" | tee -a "$LOG_FILE"
        sudo apt update
        sudo apt install -y curl wget git unzip dialog ca-certificates jq
    elif [[ $DISTRO == "Debian" ]]; then
        echo -e "${BLUE}تطبيق إعدادات مخصصة لـ Debian...${NC}" | tee -a "$LOG_FILE"
        sudo apt update
        sudo apt install -y curl wget git unzip dialog ca-certificates jq
    elif [[ $DISTRO == "CentOS" ]]; then
        echo -e "${BLUE}تطبيق إعدادات مخصصة لـ CentOS...${NC}" | tee -a "$LOG_FILE"
        sudo yum update -y
        sudo yum install -y curl wget git unzip dialog ca-certificates jq
    else
        echo -e "${RED}التوزيعة غير مدعومة${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# تغيير كلمة مرور root
change_root_password() {
    echo -e "${BLUE}\nتغيير كلمة مرور root...${NC}" | tee -a "$LOG_FILE"
    passwd root
}

# إعداد جدار الحماية
setup_firewall() {
    read -p "هل تريد إعداد جدار الحماية؟ (y/n): " FIREWALL_CONFIRM
    if [[ $FIREWALL_CONFIRM == [yY] ]]; then
        echo -e "${BLUE}\nإعداد جدار الحماية...${NC}" | tee -a "$LOG_FILE"
        sudo ufw allow 2083/tcp
        sudo ufw allow 8069/tcp
        sudo ufw enable
    else
        echo -e "${YELLOW}تحذير: لم يتم إعداد جدار الحماية. من المهم إعداد جدار الحماية لحماية السيرفر.${NC}" | tee -a "$LOG_FILE"
    fi
}

# إعداد تجديد الشهادة التلقائي باستخدام Certbot
setup_certbot_renewal() {
    echo -e "${BLUE}\nإعداد تجديد الشهادة التلقائي باستخدام Certbot...${NC}" | tee -a "$LOG_FILE"
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
}

# التأكد من تثبيت screen و nohup
ensure_screen_nohup_installed() {
    echo -e "${BLUE}\nالتأكد من تثبيت screen و nohup...${NC}" | tee -a "$LOG_FILE"
    sudo apt install -y screen
    sudo apt install -y coreutils
}

# استخدام screen أو nohup لضمان استمرار عملية التثبيت
use_screen_or_nohup() {
    read -p "هل تريد استخدام screen أو nohup لضمان استمرار عملية التثبيت؟ (s/n): " CONTINUE_METHOD
    if [[ $CONTINUE_METHOD == [sS] ]]; then
        echo -e "${BLUE}\nاستخدام screen لضمان استمرار عملية التثبيت...${NC}" | tee -a "$LOG_FILE"
        screen -S hestia_install -d -m sudo ./installer.sh
    elif [[ $CONTINUE_METHOD == [nN] ]]; then
        echo -e "${BLUE}\nاستخدام nohup لضمان استمرار عملية التثبيت...${NC}" | tee -a "$LOG_FILE"
        nohup sudo ./installer.sh > install.log 2>&1 &
    else
        echo -e "${YELLOW}سيتم متابعة التثبيت بدون استخدام screen أو nohup.${NC}" | tee -a "$LOG_FILE"
    fi
}

# التنفيذ الرئيسي
detect_environment
validate_inputs
ensure_screen_nohup_installed
use_screen_or_nohup
install_hestia
install_odoo
add_odoo_to_hestia_quick_app
setup_cloudflare
change_root_password
setup_firewall
setup_certbot_renewal
final_setup

echo -e "${YELLOW}\nملاحظة: تم توليد كلمة مرور عشوائية لهيستيا، تحقق من البريد الإلكتروني${NC}"
