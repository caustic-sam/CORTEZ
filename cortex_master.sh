#!/usr/bin/env bash
# rpicortex-init.sh — Raspberry Pi 5 Docker host bootstrap
# Version: v1.0 (HAT-aware, fleet-ready)
# Target: Raspberry Pi OS Bookworm (64-bit). Run as root (sudo).

set -euo pipefail

### =================== CONFIG ===================
HOSTNAME_DEFAULT="rpicortex"
TZ_DEFAULT="America/Chicago"
DOCKER_CHANNEL="stable"     # or "test"

# Toggleables
ENABLE_SSH="yes"
ENABLE_UFW="yes"
ENABLE_FAIL2BAN="yes"
ENABLE_ZRAM="yes"
ENABLE_AVAHI="yes"          # mDNS: rpicortex.local
ENABLE_BORG="yes"           # borgmatic nightly backups
ENABLE_WEEKLY_HEALTH="yes"  # TRIM/SMART/sensors/prune
ENABLE_ANSIBLE_PULL="no"    # set "yes" when your repo is ready

# Service accounts
STACK_USER="svc_stack"
BACKUP_USER="svc_backup"

# Data mount policy (external storage later)
DATA_MOUNT="/mnt/data"

# AI HAT (13 TOPS) — generic hooks; tighten when vendor details are known
AI_HAT_ENABLE="yes"
AI_HAT_GROUP="npu"
AI_HAT_VENDOR_NAME="aihat"
AI_HAT_UDEV_MATCH='KERNEL=="npu*", MODE="0660", GROUP="npu"'

# Ansible pull (only used if ENABLE_ANSIBLE_PULL=yes)
ANSIBLE_REPO="git@github.com:caustic-sam/pi-fleet.git"
ANSIBLE_BRANCH="main"
ANSIBLE_ARGS="-i inventories/site/hosts.yml playbooks/site.yml"

# Backup target (adjust to your NAS/S3)
BORG_REPO="ssh://backup@nas.lan:22/~/borg/rpicortex"
BORG_PASSPHRASE="CHANGE_ME"   # TODO: rotate; consider sops/age later
### ==============================================

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo: sudo bash $0"; exit 1
  fi
}

assert_arm64() {
  if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "Warning: 64-bit Raspberry Pi OS (aarch64) recommended for Docker & AI HAT." >&2
  fi
}

section(){ echo -e "\n=== $* ==="; }

apt_hygiene() {
  section "APT hygiene + base tooling"
  mkdir -p /etc/apt/keyrings /etc/rpicortex
  apt-get update -y
  apt-get install -y \
    ca-certificates gnupg lsb-release apt-transport-https \
    curl wget git jq htop unzip ripgrep net-tools \
    ufw fail2ban avahi-daemon avahi-utils \
    build-essential python3-full python3-pip \
    zram-tools powertop lm-sensors smartmontools nvme-cli hdparm \
    pciutils usbutils util-linux rsync
}

hostname_timezone() {
  section "Hostname & Timezone"
  local hn="${1:-$HOSTNAME_DEFAULT}" tz="${2:-$TZ_DEFAULT}"
  echo "$hn" >/etc/hostname
  hostnamectl set-hostname "$hn"
  timedatectl set-timezone "$tz"
}

ssh_setup() {
  section "SSH (enable + basic hardening)"
  if [[ "$ENABLE_SSH" == "yes" ]]; then
    systemctl enable --now ssh
    # Disable password auth if user has authorized_keys
    local user="${SUDO_USER:-${USER}}"
    if [[ -f "/home/${user}/.ssh/authorized_keys" ]]; then
      sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    fi
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart ssh || true
  fi
}

network_sysctl() {
  section "Sysctl (containers & networking)"
  cat >/etc/sysctl.d/99-rpicortex.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
vm.swappiness=10
fs.inotify.max_user_watches=524288
EOF
  sysctl --system
}

zram_swap() {
  [[ "$ENABLE_ZRAM" == "yes" ]] || return
  section "Enable ZRAM swap (reduce USB SSD wear)"
  cat >/etc/default/zramswap <<'EOF'
ALGO=zstd
PERCENT=25
PRIORITY=100
EOF
  systemctl enable --now zramswap.service
}

gpu_mem_headless() {
  section "Reduce GPU memory for headless use"
  if ! grep -q "^gpu_mem=" /boot/firmware/config.txt 2>/dev/null; then
    echo "gpu_mem=16" >> /boot/firmware/config.txt || true
  else
    sed -i 's/^gpu_mem=.*/gpu_mem=16/' /boot/firmware/config.txt || true
  fi
}

docker_install() {
  section "Docker Engine + Compose (official repo)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME $DOCKER_CHANNEL" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  # sane defaults
  mkdir -p /etc/docker
  cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "features": { "cdi": true }
}
EOF
  systemctl enable --now docker
}

service_accounts() {
  section "Create service accounts (stack/backup)"
  id -u "$STACK_USER" &>/dev/null || useradd -m -s /bin/bash "$STACK_USER"
  id -u "$BACKUP_USER" &>/dev/null || useradd -m -s /bin/bash "$BACKUP_USER"
  usermod -aG docker "$STACK_USER" || true
  groupadd -f stack
  usermod -aG stack "$STACK_USER"
  # minimal sudo for stack ops (docker + systemctl)
  cat >/etc/sudoers.d/80-stack <<'EOF'
%stack ALL=(root) NOPASSWD:/usr/bin/systemctl, /usr/bin/docker, /usr/bin/docker-compose, /usr/bin/docker\ *
EOF
  chmod 440 /etc/sudoers.d/80-stack
}

compose_scaffold() {
  section "Docker project scaffold"
  mkdir -p /opt/containers/{pi-hole,home-assistant,jellyfin,traefik,portainer,watchtower}/data
  mkdir -p /opt/containers/_env
  chown -R "$STACK_USER":stack /opt/containers
  chmod -R g+rw /opt/containers

  cat >/opt/containers/_env/rpicortex.example.env <<'EOF'
# Copy to rpicortex.env and edit
TZ=America/Chicago
DOMAIN=example.lan
PIHOLE_WEBPASSWORD=changeMe!
TRAEFIK_EMAIL=you@example.com
EOF

  # Starter compose (Traefik + Pi-hole) + optional services commented
  cat >/opt/containers/docker-compose.yml <<'EOF'
services:
  traefik:
    image: traefik:v3.1
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/data:/etc/traefik
    restart: unless-stopped

  pihole:
    image: pihole/pihole:latest
    environment:
      - TZ=${TZ}
      - WEBPASSWORD=${PIHOLE_WEBPASSWORD}
    volumes:
      - ./pi-hole/data/etc-pihole:/etc/pihole
      - ./pi-hole/data/etc-dnsmasq.d:/etc/dnsmasq.d
    dns:
      - 127.0.0.1
      - 1.1.1.1
    network_mode: "host"
    cap_add: [ "NET_ADMIN" ]
    restart: unless-stopped

  # portainer:
  #   image: portainer/portainer-ce:latest
  #   ports: ["9443:9443"]
  #   volumes:
  #     - /var/run/docker.sock:/var/run/docker.sock
  #     - ./portainer/data:/data
  #   restart: unless-stopped

  # watchtower:
  #   image: containrrr/watchtower
  #   command: --cleanup --interval 43200
  #   volumes:
  #     - /var/run/docker.sock:/var/run/docker.sock
  #   restart: unless-stopped
EOF

  # Allow stack user to control the compose stack
#[ - Adding a conservative TimeoutStartSec to the generated unit so systemd waits slightly longer for compose up. This is idempotent: it only changes the template written to /etc/systemd/system. ]
  cat >/etc/systemd/system/rpicortex-stack@.service <<'UNIT'
[Unit]
Description=Manage rpicortex docker compose (up/down)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=svc_stack
Group=stack
WorkingDirectory=/opt/containers
RemainAfterExit=yes
# Allow longer startup time for complex compose stacks; safe and non-destructive.
TimeoutStartSec=120
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
UNIT
}

security_basics() {
  section "Firewall, Fail2Ban, updates"
  if [[ "$ENABLE_UFW" == "yes" ]]; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw --force enable
  fi
  [[ "$ENABLE_FAIL2BAN" == "yes" ]] && systemctl enable --now fail2ban
  apt-get install -y unattended-upgrades apt-listchanges
  dpkg-reconfigure -plow unattended-upgrades
}

avahi_mdns() {
  [[ "$ENABLE_AVAHI" == "yes" ]] || return
  section "mDNS (avahi) — reach host at hostname.local"
  systemctl enable --now avahi-daemon
}

power_thermal_tools() {
  section "Power & thermals + TRIM"
  systemctl enable --now fstrim.timer || true
  sensors || true
}

active_cooler_notes() {
  section "Active Cooler — quick telemetry"
  echo "Thermal zones:"
  ls -1 /sys/class/thermal/thermal_zone* 2>/dev/null || true
  echo "Current temps (°C):"
  awk '{printf "%s\n",$1/1000"°C"}' /sys/class/thermal/thermal_zone*/temp 2>/dev/null || true
  cat >/etc/rpicortex/fan-notes.txt <<'EOF'
Pi 5 Active Cooler is firmware-controlled. Aim <80–85°C under sustained load to avoid throttling.
Tune only if your real workloads run hot.
EOF
}

storage_prep() {
  section "Storage prep — /mnt/data policy, SSD-friendly defaults"
  mkdir -p "$DATA_MOUNT"
  chown "$STACK_USER":stack "$DATA_MOUNT"

  if ! grep -q "rpicortex-data" /etc/fstab; then
    cat >>/etc/fstab <<'EOF'
# === rpicortex external data mount (uncomment/adjust after adding disk) ===
# Label your ext4 volume:
#   sudo e2label /dev/sdX1 rpicortex-data
# Then uncomment next line:
# LABEL=rpicortex-data   /mnt/data   ext4   noatime,discard,errors=remount-ro   0 2
EOF
  fi

  cat >/usr/local/bin/rpi-disk-health <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "=== TRIM ==="
/sbin/fstrim -v / || true
/sbin/fstrim -v /mnt/data || true
echo "=== SMART ==="
/usr/sbin/smartctl -H -A /dev/sda || true
/usr/sbin/smartctl -H -A /dev/nvme0 || true
EOF
  chmod +x /usr/local/bin/rpi-disk-health
}

ai_hat_setup() {
  [[ "$AI_HAT_ENABLE" == "yes" ]] || return
  section "AI HAT (13 TOPS) — PCIe sanity, udev, Docker device rules"

  echo "- lspci summary:"
  lspci || true
  echo "- /dev nodes (npu* if present):"
  ls -l /dev/npu* 2>/dev/null || true

  getent group "$AI_HAT_GROUP" >/dev/null || groupadd --system "$AI_HAT_GROUP"
  usermod -aG "$AI_HAT_GROUP" "$STACK_USER" || true

  cat >/etc/udev/rules.d/90-${AI_HAT_VENDOR_NAME}-npu.rules <<EOF
# AI HAT NPU access — tighten when vendor IDs are known
${AI_HAT_UDEV_MATCH}
EOF
  udevadm control --reload-rules && udevadm trigger || true

  mkdir -p /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/10-npu.conf <<'EOF'
[Service]
Environment="DOCKER_OPTS=--device-cgroup-rule=c 189:* rmw --device-cgroup-rule=c 240:* rmw"
EOF
  systemctl daemon-reload
  systemctl restart docker || true

  cat >/etc/rpicortex/ai-hat-readme.txt <<'EOF'
[AI HAT SDK/RUNTIME PLACEHOLDER]
Install the vendor runtime & SDK. After install:
- Verify /dev/npu* (or vendor-specific) exists
- Run vendor sample ("hello world")
- For Docker workloads:
    docker run --rm -it --device /dev/npu0 your-image:tag
Tighten /etc/udev/rules.d/90-*.rules to vendor VID/PID or subsystem when known.
EOF
}

timers_borgmatic() {
  [[ "$ENABLE_BORG" == "yes" ]] || return
  section "Borgmatic nightly backups"
  apt-get install -y borgbackup borgmatic
  mkdir -p /etc/borgmatic /root/.config/borg
  cat >/etc/borgmatic/config.yaml <<YAML
location:
  source_directories:
    - /opt/containers
    - ${DATA_MOUNT}
  repositories:
    - ${BORG_REPO}
storage:
  encryption_passphrase: "${BORG_PASSPHRASE}"
  compression: zstd
retention:
  keep_daily: 7
  keep_weekly: 4
  keep_monthly: 6
hooks:
  on_error: ["logger", "borgmatic failed on rpicortex"]
YAML

  cat >/etc/systemd/system/borgmatic.service <<'UNIT'
[Unit]
Description=Borgmatic backup

[Service]
Type=oneshot
ExecStart=/usr/bin/borgmatic --verbosity 1 --syslog-verbosity 1
UNIT

  cat >/etc/systemd/system/borgmatic.timer <<'UNIT'
[Unit]
Description=Nightly borgmatic

[Timer]
OnCalendar=03:20
Persistent=true

[Install]
WantedBy=timers.target
UNIT

  systemctl enable --now borgmatic.timer
}

timers_weekly_health() {
  [[ "$ENABLE_WEEKLY_HEALTH" == "yes" ]] || return
  section "Weekly health + housekeeping"
  cat >/usr/local/bin/rpi-weekly-health <<'SH'
#!/usr/bin/env bash
set -euo pipefail
date
echo "[TRIM]"
/sbin/fstrim -v / || true
/sbin/fstrim -v /mnt/data || true
echo "[SMART]"
/usr/sbin/smartctl -H -A /dev/sda || true
/usr/sbin/smartctl -H -A /dev/nvme0 || true
echo "[Thermals]"
sensors || true
echo "[Docker prune]"
/usr/bin/docker system prune -f
SH
  chmod +x /usr/local/bin/rpi-weekly-health

  cat >/etc/systemd/system/rpi-weekly-health.service <<'UNIT'
[Unit]
Description=Weekly health + housekeeping

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rpi-weekly-health
UNIT

  cat >/etc/systemd/system/rpi-weekly-health.timer <<'UNIT'
[Unit]
Description=Weekly health + housekeeping timer

[Timer]
OnCalendar=Sun *-*-* 04:30:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

  systemctl enable --now rpi-weekly-health.timer
}

timers_ansible_pull() {
  [[ "$ENABLE_ANSIBLE_PULL" == "yes" ]] || return
  section "Ansible pull (hourly)"
  apt-get install -y ansible git
  cat >/usr/local/bin/ansible-pull-rpicortex <<SH
#!/usr/bin/env bash
set -e
ansible-pull -U "${ANSIBLE_REPO}" -C "${ANSIBLE_BRANCH}" ${ANSIBLE_ARGS}
SH
  chmod +x /usr/local/bin/ansible-pull-rpicortex

  cat >/etc/systemd/system/ansible-pull-rpicortex.service <<'UNIT'
[Unit]
Description=Run ansible-pull for rpicortex

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ansible-pull-rpicortex
UNIT

  cat >/etc/systemd/system/ansible-pull-rpicortex.timer <<'UNIT'
[Unit]
Description=Ansible pull for rpicortex

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT

  systemctl enable --now ansible-pull-rpicortex.timer
}

post_summary() {
  section "Done. Summary"
  echo "Hostname:        $(hostname)"
  echo "Timezone:        $(timedatectl | awk -F': ' '/Time zone/ {print $2}')"
  echo "Docker:          $(docker --version 2>/dev/null || echo 'not installed')"
  echo "Compose plugin:  $(docker compose version 2>/dev/null || echo 'not installed')"
  echo "Service users:   ${STACK_USER}, ${BACKUP_USER}"
  echo "Data mount:      ${DATA_MOUNT} (fstab template present)"
  echo "AI HAT group:    ${AI_HAT_GROUP} (svc_stack added)"
  echo
  echo "Next:"
  echo "1) Log out/in to refresh groups (docker, stack, npu)."
  echo "2) Optional: label your data disk and enable the fstab line, then mount:"
  echo "     sudo e2label /dev/sdX1 rpicortex-data && sudoedit /etc/fstab && sudo mount -a"
  echo "3) cd /opt/containers && cp _env/rpicortex.example.env _env/rpicortex.env && edit."
  echo "4) Enable stack at boot (compose up) with:"
  echo "     sudo systemctl enable --now rpicortex-stack@up.service"
  echo "   Stop stack:"
  echo "     sudo systemctl stop rpicortex-stack@up.service && sudo systemctl start rpicortex-stack@down.service"
  echo "5) Consider Tailscale SSH (admin via SSO), and Authelia/Authentik behind Traefik later."
}

main() {
  require_root
  assert_arm64
  apt_hygiene
  hostname_timezone "$HOSTNAME_DEFAULT" "$TZ_DEFAULT"
  ssh_setup
  network_sysctl
  [[ "$ENABLE_ZRAM" == "yes" ]] && zram_swap
  gpu_mem_headless
  docker_install
  service_accounts
  compose_scaffold
  security_basics
  avahi_mdns
  power_thermal_tools
  active_cooler_notes
  storage_prep
  ai_hat_setup
  timers_borgmatic
  timers_weekly_health
  timers_ansible_pull
  post_summary
}

main "$@"
