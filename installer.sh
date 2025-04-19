#!/bin/bash
# Hestia-Odoo Interactive Installer
# Version: 2.0
# Author: Jaksws Team

set -e
trap 'echo "An error occurred. Exiting..."; exit 1' ERR

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

# Uninstall HestiaCP if already installed
uninstall_hestia() {
    echo -e "${BLUE}\nجاري إزالة HestiaCP...${NC}" | tee -a "$LOG_FILE"
    sudo /usr/local/hestia/bin/v-uninstall --force
    sudo rm -rf /usr/local/hestia

    # Verify successful uninstallation of HestiaCP
    if [ ! -d "/usr/local/hestia" ] && ! sudo systemctl status hestia &>/dev/null && ! ps aux | grep -q '[h]estia'; then
        echo -e "${GREEN}HestiaCP uninstalled successfully.${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}Failed to uninstall HestiaCP.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# طلب المدخلات
read -p "أدخل اسم النطاق الرئيسي (مثال: jaksws.com): " DOMAIN
SERVER_IP=$(curl -s ifconfig.me)
read -p "أدخل عنوان IP الخاص بالسيرفر (الافتراضي: $SERVER_IP): " SERVER_IP
SERVER_IP=${SERVER_IP:-$(curl -s ifconfig.me)}
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
        --multiphp '8.2,8.3,8.4' \
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
    sudo -u odoo git clone https://github.com/odoo/odoo.git --depth 1 --branch $ODOO_VERSION --single-branch /opt/odoo/src
    
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

    echo -e "${BLUE}\n جاري إعداد Cloudflare DNS...${NC}" | tee -a "$LOG_FILE"
    
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
    echo -e "${BLUE}\n اكتشاف البيئة وتطبيق أفضل الإعدادات...${NC}" | tee -a "$LOG_FILE"
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
    echo -e "${BLUE}\n تغيير كلمة مرور root...${NC}" | tee -a "$LOG_FILE"
    passwd root
}

# إعداد جدار الحماية
setup_firewall() {
    read -p "هل تريد إعداد جدار الحماية؟ (y/n): " FIREWALL_CONFIRM
    if [[ $FIREWALL_CONFIRM == [yY] ]]; then
        echo -e "${BLUE}\n إعداد جدار الحماية...${NC}" | tee -a "$LOG_FILE"
        sudo ufw allow 2083/tcp
        sudo ufw allow 8069/tcp
        sudo ufw enable
    else
        echo -e "${YELLOW}تحذير: لم يتم إعداد جدار الحماية. من المهم إعداد جدار الحماية لحماية السيرفر.${NC}" | tee -a "$LOG_FILE"
    fi
}

# إعداد تجديد الشهادة التلقائي باستخدام Certbot
setup_certbot_renewal() {
    echo -e "${BLUE}\n إعداد تجديد الشهادة التلقائي باستخدام Certbot...${NC}" | tee -a "$LOG_FILE"
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
}

# التأكد من تثبيت screen و nohup
ensure_screen_nohup_installed() {
    echo -e "${BLUE}\n التأكد من تثبيت screen و nohup...${NC}" | tee -a "$LOG_FILE"
    sudo apt install -y screen
    sudo apt install -y coreutils
}

# استخدام screen أو nohup لضمان استمرار عملية التثبيت
use_screen_or_nohup() {
    read -p "هل تريد استخدام screen أو nohup لضمان استمرار عملية التثبيت؟ (s/n): " CONTINUE_METHOD
    if [[ $CONTINUE_METHOD == [sS] ]]; then
        echo -e "${BLUE}\n استخدام screen لضمان استمرار عملية التثبيت...${NC}" | tee -a "$LOG_FILE"
        screen -S hestia_install -d -m sudo ./installer.sh
    elif [[ $CONTINUE_METHOD == [nN] ]]; then
        echo -e "${BLUE}\n استخدام nohup لضمان استمرار عملية التثبيت...${NC}" | tee -a "$LOG_FILE"
        nohup sudo ./installer.sh > install.log 2>&1 &
    else
        echo -e "${YELLOW}سيتم متابعة التثبيت بدون استخدام screen أو nohup.${NC}" | tee -a "$LOG_FILE"
    fi
}

# إعداد Nginx كوكيل عكسي
setup_nginx_reverse_proxy() {
    echo -e "${BLUE}\n إعداد Nginx كوكيل عكسي...${NC}" | tee -a "$LOG_FILE"
    sudo apt install -y nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx

    sudo mkdir -p /etc/nginx/sites-{available,enabled}
    sudo tee /etc/nginx/sites-available/odoo <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${ODOO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx
}

# التنفيذ الرئيسي
detect_environment
validate_inputs
ensure_screen_nohup_installed
use_screen_or_nohup
uninstall_hestia
install_hestia
install_odoo
add_odoo_to_hestia_quick_app
setup_cloudflare
change_root_password
setup_firewall
setup_certbot_renewal
setup_nginx_reverse_proxy
final_setup

echo -e "${YELLOW}\n ملاحظة: تم توليد كلمة مرور عشوائية لهيستيا، تحقق من البريد الإلكتروني${NC}"

# Add a section to install system dependencies
install_dependencies() {
    echo -e "${BLUE}\nUpdating system and installing dependencies...${NC}" | tee -a "$LOG_FILE"
    sudo apt update && sudo apt full-upgrade -y
    sudo apt install -y curl wget git unzip dialog ca-certificates jq python3-dev python3-pip python3.10-venv
}

# Add a section to download and prepare the script
download_prepare_script() {
    echo -e "${BLUE}\nDownloading and preparing the script...${NC}" | tee -a "$LOG_FILE"
    wget https://raw.githubusercontent.com/jaksws/hestia-odoo-installer/main/installer.sh
    chmod +x installer.sh
    dos2unix installer.sh
}

# Add a section for safe execution with monitoring using screen
safe_execution_with_monitoring() {
    echo -e "${BLUE}\nUsing screen for persistent installation...${NC}" | tee -a "$LOG_FILE"
    screen -S hestia_install -L -Logfile install.log ./installer.sh --install
}

# Add a section for installation verification
installation_verification() {
    echo -e "${BLUE}\nVerifying installation...${NC}" | tee -a "$LOG_FILE"
    curl -k https://localhost:2083 && echo "HestiaCP working properly" || echo "HestiaCP verification failed"
    curl -I http://localhost:8069 && echo "Odoo working properly" || echo "Odoo verification failed"
    tail -n 50 install.log | grep "ERROR\|WARN\|INFO"
}

# Add a section for advanced security settings
advanced_security_settings() {
    echo -e "${BLUE}\nConfiguring advanced security settings...${NC}" | tee -a "$LOG_FILE"
    # Firewall Configuration
    sudo ufw allow 2083/tcp   # HestiaCP
    sudo ufw allow 8069/tcp   # Odoo
    sudo ufw allow 443/tcp    # HTTPS
    sudo ufw enable

    # Install Fail2ban
    sudo apt install -y fail2ban
    sudo systemctl start fail2ban
    sudo systemctl enable fail2ban
}

# Add a section for HTTPS configuration with Certbot
https_configuration_with_certbot() {
    read -p "Enter your domain (e.g. odoo.example.com): " DOMAIN
    sudo apt install -y certbot
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

    # Nginx Configuration
    sudo tee /etc/nginx/sites-available/odoo <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8069;
        include proxy_params;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Enhanced Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval';";
}
EOL

    # Activate Configuration
    sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx
}

# Add a section for Docker integration
docker_integration() {
    # Install Docker
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker $USER
    fi

    # Docker Compose Configuration
    read -p "Enter database name: " DB_NAME
    read -p "Enter database user: " DB_USER
    DB_PASS=$(openssl rand -base64 24)

    sudo tee docker-compose.yml <<EOL
version: '3'
services:
  odoo:
    image: odoo:16
    ports:
      - "8069:8069"
    volumes:
      - odoo-data:/var/lib/odoo
    environment:
      - HOST=postgres
      - USER=$DB_USER
      - PASSWORD=$DB_PASS
    depends_on:
      - postgres

  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: $DB_USER
      POSTGRES_PASSWORD: $DB_PASS
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  odoo-data:
  postgres-data:
EOL

    # Start Containers
    docker-compose up -d
}

# Add a section for automatic backup system
automatic_backup_system() {
    # Create Backup Script
    sudo tee /usr/local/bin/odoo-backup <<EOL
#!/bin/bash
BACKUP_DIR="/backups/odoo"
mkdir -p \$BACKUP_DIR
docker exec \$(docker ps -aqf "name=postgres") pg_dump -U $DB_USER $DB_NAME > \$BACKUP_DIR/\$(date +%F).sql
tar -czf \$BACKUP_DIR/\$(date +%F).tar.gz /var/lib/docker/volumes
EOL

    # Configure Cron Job
    sudo chmod +x /usr/local/bin/odoo-backup
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/odoo-backup") | crontab -
}

# Add a section for troubleshooting
troubleshooting() {
    function check_errors() {
        echo -e "${BLUE}\nChecking for common issues...${NC}" | tee -a "$LOG_FILE"
        # Check port conflicts
        ss -tulpn | grep '8069\|5432'
        
        # Check service status
        systemctl status nginx postgresql docker
        
        # Check logs
        tail -50 /var/log/nginx/error.log
        docker logs $(docker ps -aqf "name=odoo")
    }
}

# Main execution
install_dependencies
download_prepare_script
safe_execution_with_monitoring
installation_verification
advanced_security_settings
https_configuration_with_certbot
docker_integration
automatic_backup_system
troubleshooting

# Full reboot step
sudo reboot

# Re-execute the script after corrections
sudo ./installer.sh --install 2>&1 | tee install.log
