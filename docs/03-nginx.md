# 03 — Nginx: Virtual Host, PHP-FPM Integration & HTTPS (Certbot)

**Role in the stack:** Nginx accepts external HTTP/HTTPS traffic (allowed by UFW in [Step 02](02-vps.md)), serves static assets from `/var/www/<DOMAIN>/public`, forwards `.php` requests to PHP 8.2-FPM over `unix:/run/php/php8.2-fpm.sock`, and terminates TLS.

---

## 1. Install & Enable Nginx

```bash
sudo apt update && sudo apt install -y nginx
sudo systemctl enable --now nginx
```

Remove the default site symlink if you do not need it:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
```

## 2. Deploy the Hardened Server Block

Copy [templates/nginx/site.conf.example](../templates/nginx/site.conf.example) to `/etc/nginx/sites-available/<DOMAIN>.conf` and replace every `<DOMAIN>` with your actual domain name.

Enable the site, validate syntax, and reload Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/<DOMAIN>.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Security Controls Included in `site.conf.example`
- **`server_tokens off;`** — hides the Nginx version from HTTP headers and error pages.
- **`try_files $fastcgi_script_name =404;`** — blocks execution of nonexistent PHP paths even if PHP-FPM settings change.
- **`location ~ /\.(?!well-known).*`** — blocks public access to `.git`, `.env`, and `.htaccess` while keeping `/.well-known/` open for Let's Encrypt validation.
- **`location ~* ^/uploads/.*\.php$`** — prevents uploaded files from being executed as PHP.
- **`location ~* \.(env|sql|bak|log|ini|sh|conf)$`** — blocks direct downloads of sensitive files.
- **Security headers** — `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, and `Permissions-Policy`.

## 3. Enable HTTPS with Let's Encrypt (Certbot)

Make sure your domain's DNS `A` (and optional `AAAA`) record points to `<VPS_IP>` before running Certbot.

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d <DOMAIN> -d www.<DOMAIN> --redirect
```

Verify automatic certificate renewal:

```bash
sudo certbot renew --dry-run
```

> [!TIP]
> Once HTTPS is confirmed working without issues, you can enable HSTS inside the `443 ssl` block created by Certbot:
> ```nginx
> add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
> ```

## 4. End-to-End Stack Verification Checklist

Run these checks to confirm all 3 services (**SSH → VPS → Nginx**) work together cleanly:

1. **SSH ([Step 01](01-ssh.md)):**
   ```bash
   ssh vps-app "whoami && hostname"
   ssh -T git@github.com   # run on the VPS
   ```
2. **VPS ([Step 02](02-vps.md)):**
   ```bash
   sudo ufw status
   sudo systemctl is-active php8.2-fpm mariadb fail2ban
   ls -ld /var/www/<DOMAIN> ~/.my.cnf
   ```
3. **Nginx ([Step 03](03-nginx.md)):**
   ```bash
   sudo nginx -t
   sudo systemctl is-active nginx
   curl -I https://<DOMAIN>
   ```
   Confirm `curl -I` returns HTTP `200` (or expected app redirect), does **not** expose `X-Powered-By: PHP/...` or an Nginx version number, and returns `403`/`404` for `https://<DOMAIN>/.env` and `https://<DOMAIN>/.git/HEAD`.
