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
