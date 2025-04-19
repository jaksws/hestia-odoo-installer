# hestia-odoo-installer
لبدء التثبيت على نظام جديد تمامًا، اتبع هذه الخطوات بدقة:

### 1. تحديث النظام الأساسي:
```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y curl wget git unzip dialog ca-certificates
```

### 2. تنزيل السكربت وتجهيزه:
```bash
wget https://raw.githubusercontent.com/jaksws/hestia-odoo-installer/main/installer.sh
chmod +x installer.sh
dos2unix installer.sh
```

### 3. تشغيل التثبيت مع المراقبة:
```bash
sudo ./installer.sh --install 2>&1 | tee install.log
```

### 4. التحقق من المكونات الأساسية بعد التثبيت:
```bash
# التحقق من HestiaCP
curl -k https://localhost:2083

# التحقق من Odoo
curl -I http://localhost:8069

# التحقق من سجلات التثبيت
tail -f install.log
```

### 5. إعدادات ما بعد التثبيت:
```bash
# تغيير كلمة مرور root (اختياري)
# تم تضمين هذه الخطوة في السكربت، لا حاجة لإجراء إضافي

# إعداد جدار الحماية
# تم تضمين هذه الخطوة في السكربت، لا حاجة لإجراء إضافي
```

### 6. إضافة Odoo إلى قائمة التطبيقات السريعة في هيستيا:
```bash
# تم تضمين هذه الخطوة في السكربت، لا حاجة لإجراء إضافي
```

### 7. إعداد HTTPS:
```bash
# تثبيت Certbot
sudo apt install -y certbot

# الحصول على شهادة SSL
sudo certbot certonly --standalone -d example.com

# إعداد Nginx كوكيل عكسي مع SSL
sudo nano /etc/nginx/sites-available/odoo
# أضف التكوين التالي:
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# تفعيل التكوين
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# إعداد تجديد الشهادة التلقائي باستخدام Certbot
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

### 8. تكامل GitHub Copilot:
```bash
# تثبيت Visual Studio Code
sudo snap install --classic code

# تثبيت ملحق GitHub Copilot
code --install-extension GitHub.copilot

# تسجيل الدخول إلى حساب GitHub الخاص بك
# اتبع التعليمات التي تظهر على الشاشة
```

### 9. التحقق من صحة الإدخالات:
```bash
# التحقق من صحة اسم النطاق
if [[ -z "$DOMAIN" || ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "اسم النطاق غير صالح."
    exit 1
fi

# التحقق من صحة عنوان IP
if [[ -z "$SERVER_IP" || ! "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "عنوان IP غير صالح."
    exit 1
fi

# التحقق من صحة منفذ هيستيا
if [[ -z "$HESTIA_PORT" || ! "$HESTIA_PORT" =~ ^[0-9]{1,5}$ || "$HESTIA_PORT" -lt 1 || "$HESTIA_PORT" -gt 65535 ]]; then
    echo "منفذ هيستيا غير صالح."
    exit 1
fi

# التحقق من صحة إصدار Odoo
if [[ -z "$ODOO_VERSION" || ! "$ODOO_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "إصدار Odoo غير صالح."
    exit 1
fi

# التحقق من صحة منفذ Odoo
if [[ -z "$ODOO_PORT" || ! "$ODOO_PORT" =~ ^[0-9]{1,5}$ || "$ODOO_PORT" -lt 1 || "$ODOO_PORT" -gt 65535 ]]; then
    echo "منفذ Odoo غير صالح."
    exit 1
fi

# التحقق من صحة مفتاح API الخاص بـ Cloudflare
if [[ -n "$CF_API" && ! "$CF_API" =~ ^[a-zA-Z0-9]{32}$ ]]; then
    echo "مفتاح API الخاص بـ Cloudflare غير صالح."
    exit 1
fi

# التحقق من صحة البريد الإلكتروني الخاص بـ Cloudflare
if [[ -n "$CF_EMAIL" && ! "$CF_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "البريد الإلكتروني الخاص بـ Cloudflare غير صالح."
    exit 1
fi

# التحقق من صحة معرف المنطقة الخاص بـ Cloudflare
if [[ -n "$CF_ZONE" && ! "$CF_ZONE" =~ ^[a-zA-Z0-9]{32}$ ]]; then
    echo "معرف المنطقة الخاص بـ Cloudflare غير صالح."
    exit 1
fi
```

### إذا واجهتك أي مشاكل، جرب هذه الحلول:

#### أ. مشكلة في تبعيات Python:
```bash
sudo apt install -y python3-dev python3-pip python3-venv
```

#### ب. مشكلة في PostgreSQL:
```bash
sudo systemctl restart postgresql
sudo -u postgres psql -c "CREATE USER odoo WITH PASSWORD 'odoo';"
```

#### ج. مشكلة في Cloudflare API:
```bash
# إعادة تكوين DNS يدويًا
sudo nano installer.sh
# ابحث عن قسم Cloudflare وأدخل API keys يدويًا
```

#### د. إعادة التثبيت الكامل:
```bash
sudo ./installer.sh --uninstall
sudo rm -rf /usr/local/hestia /opt/odoo
sudo ./installer.sh --install
```

أرسل لي مخرجات الأمر التالي إذا استمرت المشكلة:
```bash
tail -n 50 install.log
```

### 10. خطوات التثبيت على بيئة أوبنتو:
```bash
# تحديث النظام الأساسي
sudo apt update && sudo apt full-upgrade -y

# تثبيت التبعيات الأساسية
sudo apt install -y curl wget git unzip dialog ca-certificates

# تنزيل السكربت وتجهيزه
wget https://raw.githubusercontent.com/jaksws/hestia-odoo-installer/main/installer.sh
chmod +x installer.sh
dos2unix installer.sh

# تشغيل التثبيت مع المراقبة
sudo ./installer.sh --install 2>&1 | tee install.log

# التحقق من المكونات الأساسية بعد التثبيت
curl -k https://localhost:2083
curl -I http://localhost:8069
tail -f install.log

# إعدادات ما بعد التثبيت
sudo passwd root
sudo ufw allow 2083/tcp
sudo ufw allow 8069/tcp
sudo ufw enable

# إعداد HTTPS
sudo apt install -y certbot
sudo certbot certonly --standalone -d example.com
sudo nano /etc/nginx/sites-available/odoo
# أضف التكوين التالي:
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name example.com;
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# تكامل GitHub Copilot
sudo snap install --classic code
code --install-extension GitHub.copilot
# تسجيل الدخول إلى حساب GitHub الخاص بك
# اتبع التعليمات التي تظهر على الشاشة
```

### 11. تثبيت إصدارات PHP 8.2, 8.3, و 8.4:
```bash
# إضافة مستودع Ondrej Sury
sudo add-apt-repository ppa:ondrej/php
sudo apt update

# تثبيت إصدارات PHP
sudo apt install -y php8.2 php8.3 php8.4

# التحقق من التثبيت
php8.2 -v
php8.3 -v
php8.4 -v
```

### 12. استخدام `screen` أو `nohup` لضمان استمرار عملية التثبيت حتى إذا تم إغلاق التيرمينال:
```bash
# استخدام `screen`
sudo apt install screen -y
screen -S hestia_install
sudo ./installer.sh
# اضغط `Ctrl+A` ثم `D` للانفصال عن الجلسة.
# أعِد الاتصال لاحقًا بـ:
screen -r hestia_install

# استخدام `nohup`
nohup sudo ./installer.sh > install.log 2>&1 &
# تابع التقدم بـ:
tail -f install.log
```

### 13. استخدام `tmux` لضمان استمرار عملية التثبيت حتى إذا تم إغلاق التيرمينال:
```bash
# استخدام `tmux`
sudo apt install tmux -y
tmux new -s hestia_install
sudo ./installer.sh
# اضغط `Ctrl+B` ثم `D` للانفصال عن الجلسة.
# أعِد الاتصال لاحقًا بـ:
tmux attach -t hestia_install
```

### 14. استخدام `systemd` لضمان استمرار عملية التثبيت حتى إذا تم إغلاق التيرمينال:
```bash
# إنشاء ملف وحدة خدمة systemd
sudo nano /etc/systemd/system/hestia_install.service
# أضف التكوين التالي:
[Unit]
Description=Hestia-Odoo Installer
After=network.target

[Service]
ExecStart=/path/to/installer.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target

# تفعيل الخدمة
sudo systemctl daemon-reload
sudo systemctl enable hestia_install.service
sudo systemctl start hestia_install.service
```

### 15. إعداد خدمة البريد الإلكتروني في هيستيا:
```bash
# تثبيت HestiaCP يتضمن خدمات البريد الإلكتروني مثل Exim و Dovecot
# لا حاجة لإجراء إضافي
```

### 16. التعامل مع الأخطاء في `installer.sh`:
```bash
# استخدام `set -e` في بداية السكربت لضمان خروج السكربت فورًا إذا فشل أي أمر
set -e

# استخدام `trap` لالتقاط الأخطاء وتنفيذ إجراءات التنظيف
trap 'echo "حدث خطأ. الخروج..."; exit 1' ERR

# التحقق من نجاح الأوامر الحرجة والتعامل مع الأخطاء وفقًا لذلك
if ! wget -q https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh; then
    echo "فشل في تنزيل سكربت HestiaCP."
    exit 1
fi

# تجنب تسجيل المعلومات الحساسة مثل كلمات المرور ومفاتيح API
```

### 17. إعداد وكيل عكسي مع SSL:
```bash
# تثبيت Nginx
sudo apt install -y nginx

# الحصول على شهادة SSL باستخدام Certbot
sudo apt install -y certbot
sudo certbot certonly --standalone -d example.com

# إعداد Nginx كوكيل عكسي مع SSL
sudo nano /etc/nginx/sites-available/odoo
# أضف التكوين التالي:
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name example.com;
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# تفعيل التكوين وإعادة تشغيل Nginx
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

### 18. اكتشاف البيئة وتطبيق أفضل الإعدادات:
```bash
# اكتشاف نظام التشغيل
OS=$(uname -s)
case $OS in
    Linux)
        DISTRO=$(lsb_release -is)
        VERSION=$(lsb_release -rs)
        echo "نظام التشغيل: $DISTRO $VERSION"
        ;;
    Darwin)
        echo "نظام التشغيل: macOS"
        ;;
    *)
        echo "نظام التشغيل غير مدعوم"
        exit 1
        ;;
esac

# تطبيق الإعدادات المخصصة بناءً على البيئة
if [[ $DISTRO == "Ubuntu" ]]; then
    echo "تطبيق إعدادات مخصصة لـ Ubuntu..."
    sudo apt update
    sudo apt install -y curl wget git unzip dialog ca-certificates jq
elif [[ $DISTRO == "Debian" ]]; then
    echo "تطبيق إعدادات مخصصة لـ Debian..."
    sudo apt update
    sudo apt install -y curl wget git unzip dialog ca-certificates jq
elif [[ $DISTRO == "CentOS" ]]; then
    echo "تطبيق إعدادات مخصصة لـ CentOS..."
    sudo yum update -y
    sudo yum install -y curl wget git unzip dialog ca-certificates jq
else
    echo "التوزيعة غير مدعومة"
    exit 1
fi
```
