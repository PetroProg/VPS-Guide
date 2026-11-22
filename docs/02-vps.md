# 02 — VPS: Ubuntu Hardening, UFW, PHP 8.2-FPM, Deployment & Backups

**Role in the stack:** The VPS hosts your application code (pulled via SSH from [Step 01](01-ssh.md)), enforces network boundaries with UFW, runs PHP 8.2-FPM for [Nginx (Step 03)](03-nginx.md), and executes automated encrypted/restricted backups.

---

## 1. System Updates & Automatic Security Patches

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ufw unattended-upgrades fail2ban software-properties-common
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Enable `fail2ban` for SSH brute-force protection:

```bash
sudo systemctl enable --now fail2ban
```

## 2. Firewall (UFW) — Safe Activation Order

Always allow SSH **before** enabling UFW so you do not lock yourself out:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow "Nginx Full"
sudo ufw enable
sudo ufw status verbose
```

> [!IMPORTANT]
> `"Nginx Full"` opens ports `80` (HTTP) and `443` (HTTPS) so [Step 03 (Nginx + Certbot)](03-nginx.md) can serve traffic and issue TLS certificates. Keep MariaDB port `3306` closed to the outside world.

## 3. Install & Harden PHP 8.2-FPM

```bash
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install -y \
    php8.2-fpm php8.2-cli php8.2-mysql php8.2-curl \
    php8.2-xml php8.2-gd php8.2-zip php8.2-mbstring php8.2-intl
```

Harden `/etc/php/8.2/fpm/php.ini`:
- Disable `cgi.fix_pathinfo` (prevents arbitrary PHP execution on crafted paths).
- Disable `expose_php` (hides PHP version in HTTP headers).
- Disable `display_errors` in production (prevents leaking stack traces/paths).

```bash
sudo sed -i 's/^\s*;*\s*cgi.fix_pathinfo\s*=.*/cgi.fix_pathinfo=0/' /etc/php/8.2/fpm/php.ini
sudo sed -i 's/^\s*;*\s*expose_php\s*=.*/expose_php = Off/' /etc/php/8.2/fpm/php.ini
sudo sed -i 's/^\s*;*\s*display_errors\s*=.*/display_errors = Off/' /etc/php/8.2/fpm/php.ini
sudo sed -i 's/^\s*;*\s*log_errors\s*=.*/log_errors = On/' /etc/php/8.2/fpm/php.ini

sudo systemctl enable --now php8.2-fpm
sudo systemctl restart php8.2-fpm
```

Verify the FastCGI socket exists (Nginx will connect to this exact socket in Step 03):

```bash
ls -la /run/php/php8.2-fpm.sock
```

## 4. Web Directory & Least-Privilege Permissions

Create the site root and deploy your code via the GitHub SSH key configured in [Step 01](01-ssh.md):

```bash
sudo mkdir -p /var/www/<DOMAIN>/public
sudo chown -R <VPS_USER>:www-data /var/www/<DOMAIN>
```

Clone or pull your repository as `<VPS_USER>` (not `root`):

```bash
git clone git@github.com:<ORG>/<REPO>.git /var/www/<DOMAIN>
```

Apply least-privilege permissions so Nginx/PHP (`www-data`) can **read** files (`750`/`640`) but cannot modify your source code:

```bash
sudo chown -R <VPS_USER>:www-data /var/www/<DOMAIN>
sudo find /var/www/<DOMAIN> -type d -exec chmod 750 {} \;
sudo find /var/www/<DOMAIN> -type f -exec chmod 640 {} \;
```

> [!TIP]
> If your application needs a writable directory (e.g., `storage/` or `uploads/`), grant group write permissions **only** to that specific directory (`chmod 770`), never to the entire `/var/www/<DOMAIN>` tree.

## 5. MariaDB & Automated Secure Backups

### 5.1 Secure MariaDB
```bash
sudo apt install -y mariadb-server
sudo systemctl enable --now mariadb
sudo mariadb-secure-installation
```

Ensure MariaDB listens only on `127.0.0.1` (`bind-address = 127.0.0.1` in `/etc/mysql/mariadb.conf.d/50-server.cnf`).

Create a dedicated least-privilege backup user (avoid using `root` in backup scripts):

```sql
CREATE USER '<DB_BACKUP_USER>'@'127.0.0.1' IDENTIFIED BY '<CHANGE_ME_STRONG_PASSWORD>';
GRANT SELECT, LOCK TABLES, SHOW VIEW, TRIGGER, EVENT, PROCESS ON `<DB_NAME>`.* TO '<DB_BACKUP_USER>'@'127.0.0.1';
FLUSH PRIVILEGES;
```

### 5.2 Configure `~/.my.cnf` (No Passwords on CLI)
Copy [templates/db/my.cnf.example](../templates/db/my.cnf.example) to `~/.my.cnf` on the VPS, fill in `<DB_BACKUP_USER>` and password, and lock permissions:

```bash
chmod 600 ~/.my.cnf
```

### 5.3 Install & Schedule Backup Scripts
Copy [scripts/backup_bd.sh](../scripts/backup_bd.sh) and [scripts/backup_files.sh](../scripts/backup_files.sh) to `~/scripts/` on the VPS:

```bash
mkdir -p ~/scripts && chmod 700 ~/scripts
chmod 700 ~/scripts/backup_bd.sh ~/scripts/backup_files.sh
```

Test them manually before scheduling:

```bash
DB_NAME="<DB_NAME>" ~/scripts/backup_bd.sh
SITE_DIR="/var/www/<DOMAIN>/public" ~/scripts/backup_files.sh
```

Schedule daily cron jobs (`crontab -e`):

```cron
0 2 * * * DB_NAME="<DB_NAME>" /home/<VPS_USER>/scripts/backup_bd.sh >> /home/<VPS_USER>/backups/cron.log 2>&1
30 2 * * * SITE_DIR="/var/www/<DOMAIN>/public" /home/<VPS_USER>/scripts/backup_files.sh >> /home/<VPS_USER>/backups/cron.log 2>&1
```

Both scripts enforce `set -euo pipefail`, `umask 077` (archives created with `600` permissions), and automatic retention cleanup.

---

**Next step:** With UFW open for HTTP/HTTPS, PHP 8.2-FPM running, and `/var/www/<DOMAIN>/public` ready, proceed to [03 — Nginx Configuration & HTTPS](03-nginx.md).
