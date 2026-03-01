# VM Linux Hardening & Setup Script

Automated hardening and configuration script for fresh Ubuntu 22.04+ / Debian 12+ VMs.

## What it does

| Step | Action |
|------|--------|
| 1 | System update + install base packages + unattended-upgrades |
| 2 | Create user `<username>` (sudo, SSH key only, password locked) |
| 3 | SSH hardening (no password, no root, MaxAuthTries 3) |
| 4 | Install Tailscale + interactive `tailscale up --ssh` (enables Tailscale SSH) |
| 5 | UFW lockdown: deny all, allow `tailscale0`, rate-limit backdoor port |
| 6 | Bind SSH to Tailscale interface only (with confirmation prompt) |
| 7 | Install OpenClaw AI agent |
| 8 | Emergency backdoor (hidden port, key-only, audited, rate-limited) |
| 9 | Configure fail2ban |

## Prerequisites

- Fresh Ubuntu 22.04+ or Debian 12+ VM
- Root or sudo access
- Your SSH public key saved as **`<username>.pub`** next to `setup.sh` (e.g. `laurent.pub` for user `laurent`)

## Usage

### 1. Clone the repo on your VM

```bash
git clone https://github.com/locryns/vm-linux-hardening-setup.git
cd vm-linux-hardening-setup
```

### 2. Add your SSH public key

```bash
# Replace 'laurent' with your chosen username
# From your local machine:
scp ~/.ssh/id_ed25519.pub root@<VM_IP>:~/vm-linux-hardening-setup/<username>.pub

# Or paste it directly on the VM:
nano <username>.pub
```

### 3. Run the script

```bash
# Pass your username as argument
sudo bash setup.sh <username>
```

### Options

```bash
# Dry run (no changes made, preview only)
sudo DRY_RUN=1 bash setup.sh <username>

# Custom backdoor port
sudo BACKDOOR_PORT=59999 bash setup.sh <username>
```

## After the script

1. **Test Tailscale SSH** (before closing your current session!):
   ```bash
   # Tailscale SSH (recommended — no host key needed)
   tailscale ssh <username>@<TAILSCALE_IP>

   # Or standard SSH over the Tailscale network
   ssh <username>@<TAILSCALE_IP>
   ```

2. **Test emergency backdoor**:
   ```bash
   ssh -p 62847 <username>@<PUBLIC_IP>
   ```

3. **Onboard OpenClaw**:
   ```bash
   openclaw onboard
   ```

4. Check logs: `sudo tail -f /var/log/vm-setup.log`

## Security model

```
Internet ─── UFW (deny all) ─┬─ tailscale0 ─── Tailscale SSH (tailscale ssh) ─── <username>
                              └─ port 62847 ─── SSH (emergency, audited, rate-limited)
```

- All public traffic blocked except the emergency backdoor port
- SSH only accessible via Tailscale (`tailscale ssh <username>@<IP>`) — no host key friction
- Emergency backdoor: SSH key only, max 2 auth tries, 24h ban on failure
- Audit log: `/var/log/backdoor_access.log`
- fail2ban active on both SSH endpoints

## Files

```
vm-linux-hardening-setup/
├── setup.sh       # Main hardening script
├── <username>.pub # ⚠ YOUR SSH public key (NOT committed to git)
└── README.md
```

> ⚠ `*.pub` files are in `.gitignore` — **never commit your public key**.
