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
sudo passwd root

# إعداد جدار الحماية
sudo ufw allow 2083/tcp
sudo ufw allow 8069/tcp
sudo ufw enable
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
