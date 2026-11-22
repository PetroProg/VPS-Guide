# 01 — SSH: Bastion Access, SFTP Tunnel, Hardening & GitHub Deploy Key

**Role in the stack:** SSH is the secure entry point to your VPS and the transport layer for deploying code from GitHub and transferring files over SFTP.

---

## 1. Generate Dedicated Ed25519 Keys (Local Machine)

Use modern `ed25519` keys protected with a strong passphrase. Never reuse the same key for everything.

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_bastion -C "bastion-access"
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_vps -C "vps-access"
```

Set strict permissions on your `~/.ssh` directory (**never** use `sudo` on files inside your own `~` directory):

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_bastion ~/.ssh/id_ed25519_vps
chmod 644 ~/.ssh/id_ed25519_bastion.pub ~/.ssh/id_ed25519_vps.pub
```

## 2. Configure Local `~/.ssh/config`

Copy [templates/ssh/client-config.example](../templates/ssh/client-config.example) into `~/.ssh/config`, replace `<BASTION_IP>`, `<BASTION_USER>`, `<VPS_IP>`, and `<VPS_USER>`, then lock down permissions:

```bash
chmod 600 ~/.ssh/config
```

What the three blocks provide:
- **`bastion`**: Jump host entry point (`ForwardAgent no` prevents a compromised bastion from hijacking your local SSH agent).
- **`vps-app`**: Direct SSH into the VPS through the bastion using `ProxyJump bastion`:
  ```bash
  ssh vps-app
  ```
- **`tunnel-vps`**: Opens a localhost-only SFTP tunnel (`127.0.0.1:2222 -> 127.0.0.1:22` on the VPS) for FileZilla or SFTP clients:
  ```bash
  ssh -N tunnel-vps
  ```
  In FileZilla, connect to `sftp://127.0.0.1`, port `2222`, using `<VPS_USER>` and your `id_ed25519_vps` key.

> [!NOTE]
> Binding `LocalForward` to `127.0.0.1:2222` ensures no other device on your local network can reach the forwarded port.

## 3. Harden the SSH Server on the VPS

Once logged into the VPS (`ssh vps-app`) and verified that key-based login works, disable root login and password authentication using a drop-in file so system updates do not overwrite your settings:

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
AllowUsers <VPS_USER>
EOF
```

Replace `<VPS_USER>` with your actual sudo username, validate the syntax, and reload **while keeping your current SSH session open**:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

Open a **second terminal** and test `ssh vps-app` before closing the first session.

## 4. Configure a Read-Only GitHub Deploy Key on the VPS

Never copy your personal GitHub SSH key onto a server. Generate a dedicated key directly on the VPS:

```bash
sudo apt update && sudo apt install -y git
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_deploy -C "vps-deploy-key"
chmod 600 ~/.ssh/id_ed25519_github_deploy
```

1. Display the public key:
   ```bash
   cat ~/.ssh/id_ed25519_github_deploy.pub
   ```
2. In GitHub, open your repository → **Settings → Deploy keys → Add deploy key**, paste the public key, and leave **Allow write access** unchecked (read-only).
3. Create `~/.ssh/config` on the VPS using [templates/ssh/vps-github-config.example](../templates/ssh/vps-github-config.example) and set `chmod 600 ~/.ssh/config`.
4. Verify GitHub authentication:
   ```bash
   ssh -T git@github.com
   ```

---

**Next step:** Now that you have secure SSH access and GitHub deploy capability on the VPS, proceed to [02 — VPS Provisioning, PHP 8.2-FPM & Secure Backups](02-vps.md).
