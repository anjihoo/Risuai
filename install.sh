cat > ~/install.sh << 'EOF'
#!/bin/bash
set -e

REPO_URL="https://github.com/kwaroran/RisuAI.git"
DEFAULT_PORT="6001"
NVM_VERSION="0.40.1"
NODE_VERSION="20"

# detected
USER_NAME=""
USER_HOME=""
INSTALL_DIR=""
DISTRO_ID=""
PKG_MANAGER=""
TOTAL_RAM_MB=""

# config
VERSION_MODE=""
SHARE_MODE=""
BACKUP_MODE=""
ENABLE_HTTPS=""
CF_TOKEN=""
TS_KEY=""
RESTIC_PASS=""
RESTIC_DAYS=""

log() { echo ":: $1"; }
err() { echo "!! $1" >&2; }
die() { err "$1"; exit 1; }

detect_system() {
    if [ "$EUID" -ne 0 ]; then
        die "Please run with sudo: sudo bash $0"
    fi
    [ -n "$SUDO_USER" ] || die "Do not run as root directly. Use: sudo bash $0"
    USER_NAME="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    INSTALL_DIR="$USER_HOME/RisuAI"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        [ -n "$ID_LIKE" ] && case "$ID_LIKE" in
            *debian*|*ubuntu*) DISTRO_ID="debian" ;;
            *rhel*|*fedora*) DISTRO_ID="rhel" ;;
            *arch*) DISTRO_ID="arch" ;;
        esac
    fi

    if command -v apt-get >/dev/null; then PKG_MANAGER="apt"
    elif command -v dnf >/dev/null; then PKG_MANAGER="dnf"
    elif command -v yum >/dev/null; then PKG_MANAGER="yum"
    elif command -v pacman >/dev/null; then PKG_MANAGER="pacman"
    elif command -v zypper >/dev/null; then PKG_MANAGER="zypper"
    elif command -v apk >/dev/null; then PKG_MANAGER="apk"
    else die "Unsupported package manager"
    fi

    TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "4096")
    [ -z "$TOTAL_RAM_MB" ] && TOTAL_RAM_MB=4096 || true

    log "User: $USER_NAME"
    log "Home: $USER_HOME"
    log "Distro: $DISTRO_ID ($PKG_MANAGER)"
    log "RAM: ${TOTAL_RAM_MB}MB"
    log "Install dir: $INSTALL_DIR"
}

calc_node_mem() {
    local ram=$TOTAL_RAM_MB
    if [ "$ram" -lt 2048 ]; then echo "1024"
    elif [ "$ram" -lt 4096 ]; then echo "2048"
    elif [ "$ram" -lt 8192 ]; then echo "4096"
    else echo "8192"
    fi
}

pkg_install() {
    case "$PKG_MANAGER" in
        apt) apt-get update -qq && apt-get install -y -qq "$@" ;;
        dnf) dnf install -y -q "$@" ;;
        yum) yum install -y -q "$@" ;;
        pacman) pacman -Sy --noconfirm "$@" ;;
        zypper) zypper install -y "$@" ;;
        apk) apk add "$@" ;;
    esac
}

install_deps() {
    log "Installing dependencies..."
    local missing=""
    for cmd in curl git openssl; do
        command -v "$cmd" >/dev/null || missing="$missing $cmd"
    done
    [ -n "$missing" ] && pkg_install $missing || true
}

prompt_config() {
    echo ""
    echo "=== Configuration ==="
    echo ""

    echo "Install mode:"
    echo "  1) 새로 설치 (기존 파일 모두 제거)"
    echo "  2) 업데이트 (기존 파일 유지)"
    printf "Select [1-2]: "
    read -r INSTALL_MODE
    case "$INSTALL_MODE" in
        2) INSTALL_MODE=2 ;;
        *) INSTALL_MODE=1 ;;
    esac

    echo ""
    echo "Version mode:"
    echo "  1) release - latest stable release (recommended)"
    echo "  2) latest  - latest development (main branch)"
    echo "  3) 커스텀   - 사용자 레포지토리 (https://github.com/anjihoo/Risuai.git)"
    printf "Select [1-3]: "
    read -r VERSION_MODE
    case "$VERSION_MODE" in
        3)
            VERSION_MODE=3
            REPO_URL="https://github.com/anjihoo/Risuai.git"
            ;;
        2)
            VERSION_MODE=2 ;;
        *)
            VERSION_MODE=1 ;;
    esac

    echo ""
    echo "Share mode:"
    echo "  1) none       - localhost only (127.0.0.1)"
    echo "  2) local      - LAN access (0.0.0.0)"
    echo "  3) cloudflare - Cloudflare Tunnel"
    echo "  4) tailscale  - Tailscale VPN"
    printf "Select [1-4]: "
    read -r SHARE_MODE
    case "$SHARE_MODE" in
        2|3|4) ;;
        *) SHARE_MODE=1 ;;
    esac

    if [ "$SHARE_MODE" = "3" ]; then
        printf "Cloudflare Tunnel token (optional): "
        read -r CF_TOKEN
    elif [ "$SHARE_MODE" = "4" ]; then
        printf "Tailscale auth key (optional): "
        read -r TS_KEY
    fi

    # HTTPS option (not for none or cloudflare)
    if [ "$SHARE_MODE" = "2" ] || [ "$SHARE_MODE" = "4" ]; then
        echo ""
        echo "Self-signed HTTPS certificate:"
        echo "  1) no  - HTTP only"
        echo "  2) yes - generate certificate"
        printf "Select [1-2]: "
        read -r ENABLE_HTTPS
        case "$ENABLE_HTTPS" in
            2) ENABLE_HTTPS=1 ;;
            *) ENABLE_HTTPS=0 ;;
        esac
    else
        ENABLE_HTTPS=0
    fi

    echo ""
    echo "Backup mode:"
    echo "  1) none   - no backup"
    echo "  2) restic - incremental backup"
    echo "  3) git    - local git repository"
    printf "Select [1-3]: "
    read -r BACKUP_MODE
    case "$BACKUP_MODE" in
        2|3) ;;
        *) BACKUP_MODE=1 ;;
    esac

    if [ "$BACKUP_MODE" = "2" ]; then
        while true; do
            printf "Restic password (empty for default): "
            read -rs RESTIC_PASS
            echo ""
            printf "Confirm password: "
            read -rs RESTIC_PASS2
            echo ""
            if [ "$RESTIC_PASS" = "$RESTIC_PASS2" ]; then
                if [ -z "$RESTIC_PASS" ]; then
                    RESTIC_PASS="risuai-backup"
                fi
                break
            else
                echo "Passwords do not match. Try again."
            fi
        done
        printf "Keep backups for how many days? [30]: "
        read -r RESTIC_DAYS
        if [ -z "$RESTIC_DAYS" ]; then
            RESTIC_DAYS=30
        elif ! [ "$RESTIC_DAYS" -eq "$RESTIC_DAYS" ] 2>/dev/null; then
            RESTIC_DAYS=30
        fi
    fi
}

install_nvm() {
    log "Installing nvm..."
    local nvm_dir="$USER_HOME/.nvm"
    export NVM_DIR="$nvm_dir"
    export HOME="$USER_HOME"
    if [ ! -d "$nvm_dir" ]; then
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash
        chown -R "$USER_NAME:$USER_NAME" "$nvm_dir"
    fi
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
}

install_node() {
    log "Installing Node.js $NODE_VERSION..."
    export HOME="$USER_HOME"
    export NVM_DIR="$USER_HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
    nvm use "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    chown -R "$USER_NAME:$USER_NAME" "$NVM_DIR"
}

install_pnpm() {
    log "Installing pnpm..."
    export HOME="$USER_HOME"
    export NVM_DIR="$USER_HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    if corepack enable 2>/dev/null; then
        corepack prepare pnpm@latest --activate 2>/dev/null || npm install -g pnpm
    else
        npm install -g pnpm
    fi
    chown -R "$USER_NAME:$USER_NAME" "$NVM_DIR"
}

clone_risuai() {
    log "Cloning RisuAI..."
    if [ -d "$INSTALL_DIR" ]; then
        log "Directory exists, fetching updates..."
        cd "$INSTALL_DIR"
        git fetch --all --tags
    else
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        git fetch --all --tags
    fi

    if [ "$VERSION_MODE" = "1" ]; then
        local latest_tag
        latest_tag=$(git tag -l --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+' | head -n1)
        if [ -n "$latest_tag" ]; then
            log "Checking out release: $latest_tag"
            git checkout "$latest_tag"
        else
            err "No release tags found, using main branch"
            git checkout main
        fi
    else
        log "Using latest development (main branch)"
        git checkout main
        git pull origin main || true
    fi

    chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
}

build_risuai() {
    log "Building RisuAI..."
    cd "$INSTALL_DIR"
    export HOME="$USER_HOME"
    export NVM_DIR="$USER_HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    export NODE_OPTIONS="--max_old_space_size=$(calc_node_mem)"
    pnpm install
    if [ "$VERSION_MODE" = "3" ]; then
        pnpm add jsonwebtoken otplib
    fi
    pnpm build
    mkdir -p "$INSTALL_DIR/save"
    chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
}

setup_https() {
    [ "$ENABLE_HTTPS" != "1" ] && return

    log "Setting up HTTPS certificates..."
    local ssl_dir="$INSTALL_DIR/server/node/ssl"
    local cert_dir="$ssl_dir/certificate"

    if [ ! -d "$ssl_dir" ]; then
        err "SSL directory not found: $ssl_dir"
        return
    fi

    if [ -d "$cert_dir" ] && [ -f "$cert_dir/server.crt" ]; then
        log "Certificates already exist, skipping..."
        return
    fi

    cd "$ssl_dir"

    local local_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$local_ip" ]; then
        local_ip="127.0.0.1"
    fi

    local ts_ip=""
    if [ "$SHARE_MODE" = "4" ] && command -v tailscale >/dev/null; then
        ts_ip=$(tailscale ip -4 2>/dev/null || true)
    fi

    if [ -f server.conf ]; then
        cp server.conf server.conf.bak
        sed -i "s/^DNS\.1.*/DNS.1 = localhost/" server.conf
        sed -i "s/^IP\.1.*/IP.1 = 127.0.0.1/" server.conf

        if ! grep -q "IP.2" server.conf; then
            sed -i "/^IP\.1/a IP.2 = $local_ip" server.conf
        fi
        if [ -n "$ts_ip" ] && ! grep -q "IP.3" server.conf; then
            sed -i "/^IP\.2/a IP.3 = $ts_ip" server.conf
        fi
    fi

    if [ -f "Generate Certificate.sh" ]; then
        bash "Generate Certificate.sh"
    else
        log "Certificate generation script not found, creating manually..."
        mkdir -p certificate
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout certificate/server.key \
            -out certificate/server.crt \
            -subj "/CN=RisuAI/O=RisuAI" \
            -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:$local_ip${ts_ip:+,IP:$ts_ip}"
        cp certificate/server.crt certificate/ca.crt
    fi

    log "HTTPS certificates generated"
}

setup_cloudflare() {
    [ "$SHARE_MODE" != "3" ] && return
    log "Setting up Cloudflare Tunnel..."

    if ! command -v cloudflared >/dev/null; then
        case "$PKG_MANAGER" in
            apt)
                mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
                apt-get update -qq && apt-get install -y -qq cloudflared
                ;;
            *)
                local arch
                arch=$(uname -m)
                case "$arch" in
                    x86_64) arch="amd64" ;;
                    aarch64) arch="arm64" ;;
                    armv7l) arch="arm" ;;
                esac
curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o /tmp/cloudflared
                mv /tmp/cloudflared /usr/local/bin/cloudflared
                chmod +x /usr/local/bin/cloudflared
                ;;
        esac
    fi

    if [ -n "$CF_TOKEN" ]; then
        if cloudflared service install "$CF_TOKEN"; then
            systemctl enable cloudflared
            systemctl start cloudflared
            log "Cloudflare Tunnel started"
        else
            err "Cloudflare service install failed. Check token or run manually:"
            err "  sudo cloudflared service install <TOKEN>"
        fi
    else
        log "No token provided. Run manually:"
        log "  sudo cloudflared service install <TOKEN>"
    fi
}

setup_tailscale() {
    [ "$SHARE_MODE" != "4" ] && return
    log "Setting up Tailscale..."

    if ! command -v tailscale >/dev/null; then
curl -fsSL https://tailscale.com/install.sh | sh
    fi

    if [ -n "$TS_KEY" ]; then
        tailscale up --authkey="$TS_KEY"
    else
        log "No auth key provided. Run manually:"
        log "  sudo tailscale up"
    fi
}

setup_restic() {
    [ "$BACKUP_MODE" != "2" ] && return
    log "Setting up Restic backup..."

    command -v restic >/dev/null || pkg_install restic
    command -v crontab >/dev/null || pkg_install cron

    local backup_dir="$USER_HOME/.risuai-backup"
    local save_dir="$INSTALL_DIR/save"
    mkdir -p "$backup_dir" "$save_dir"

    export RESTIC_REPOSITORY="$backup_dir"
    export RESTIC_PASSWORD="$RESTIC_PASS"
    if [ ! -f "$backup_dir/config" ]; then
        restic init
    fi
    chown -R "$USER_NAME:$USER_NAME" "$backup_dir" "$save_dir"

    tee /usr/local/bin/backup-risuai.sh >/dev/null <<BACKUP
#!/bin/bash
export RESTIC_REPOSITORY="$backup_dir"
export RESTIC_PASSWORD="$RESTIC_PASS"
restic backup "$save_dir" --tag "\$(date +%Y%m%d_%H%M)" 2>/dev/null
restic forget --keep-daily $RESTIC_DAYS --prune 2>/dev/null
BACKUP
    chmod +x /usr/local/bin/backup-risuai.sh
    sudo -u "$USER_NAME" bash -c "(crontab -l 2>/dev/null | grep -v backup-risuai; echo '*/10 * * * * /usr/local/bin/backup-risuai.sh') | crontab -"
    systemctl enable cron 2>/dev/null || true
    systemctl start cron 2>/dev/null || true
}

setup_git_backup() {
    [ "$BACKUP_MODE" != "3" ] && return
    log "Setting up Git backup..."

    command -v crontab >/dev/null || pkg_install cron

    local save_dir="$INSTALL_DIR/save"
    mkdir -p "$save_dir"
   
    (
        cd "$save_dir"
        if [ ! -d ".git" ]; then
            git init
            git config user.email "risuai@localhost"
            git config user.name "RisuAI Backup"
        fi
    )
    chown -R "$USER_NAME:$USER_NAME" "$save_dir"

    tee /usr/local/bin/backup-risuai.sh >/dev/null <<BACKUP
#!/bin/bash
cd "$save_dir"
git add -A
git commit -m "backup \$(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
BACKUP
    chmod +x /usr/local/bin/backup-risuai.sh
    sudo -u "$USER_NAME" bash -c "(crontab -l 2>/dev/null | grep -v backup-risuai; echo '*/10 * * * * /usr/local/bin/backup-risuai.sh') | crontab -"
    systemctl enable cron 2>/dev/null || true
    systemctl start cron 2>/dev/null || true
}

create_systemd() {
    log "Creating systemd service..."

    local bind_addr="0.0.0.0"
    [ "$SHARE_MODE" = "1" ] && bind_addr="127.0.0.1"
    [ "$SHARE_MODE" = "3" ] && bind_addr="127.0.0.1"

    local nvm_dir="$USER_HOME/.nvm"
    export HOME="$USER_HOME"
    export NVM_DIR="$nvm_dir"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    local node_bin
    node_bin=$(dirname "$(which node)")
    local node_mem
    node_mem=$(calc_node_mem)

    tee /etc/systemd/system/risuai.service >/dev/null <<SERVICE
[Unit]
Description=RisuAI Server
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$node_bin:/usr/bin:/bin
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max_old_space_size=$node_mem
Environment=PORT=$DEFAULT_PORT
Environment=HOST=$bind_addr
ExecStart=$node_bin/node $INSTALL_DIR/server/node/server.cjs
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable risuai
    systemctl start risuai
}

create_scripts() {
    log "Creating helper scripts..."
    local node_mem
    node_mem=$(calc_node_mem)

    tee "$INSTALL_DIR/start.sh" >/dev/null <<START
#!/bin/bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
cd "\$(dirname "\$0")"
export NODE_OPTIONS="--max_old_space_size=$node_mem"
exec node server/node/server.cjs
START
    chmod +x "$INSTALL_DIR/start.sh"
}

setup_bashrc() {
    local bashrc="$USER_HOME/.bashrc"
    local node_mem
    node_mem=$(calc_node_mem)
    grep -q "NODE_OPTIONS" "$bashrc" 2>/dev/null || echo "export NODE_OPTIONS=\"--max_old_space_size=$node_mem\"" >> "$bashrc"
}

print_done() {
    local proto="http"
    [ "$ENABLE_HTTPS" = "1" ] && proto="https"
   
    local url="http://127.0.0.1:$DEFAULT_PORT"
    case "$SHARE_MODE" in
        2) url="$proto://<your-ip>:$DEFAULT_PORT" ;;
        3) url="(see Cloudflare dashboard)" ;;
        4)
            local ts_ip
            ts_ip=$(tailscale ip -4 2>/dev/null || echo "<tailscale-ip>")
            url="$proto://$ts_ip:$DEFAULT_PORT"
            ;;
    esac

    local version_info="latest development"
    if [ "$VERSION_MODE" = "1" ]; then
        version_info=$(cd "$INSTALL_DIR" && git describe --tags --exact-match 2>/dev/null || echo "release")
    fi

    echo ""
    echo "=== Installation Complete ==="
    echo ""
    echo "Directory: $INSTALL_DIR"
    echo "Version: $version_info"
    echo "Access: $url"
    echo ""
    echo "Commands:"
    echo "  sudo systemctl start risuai"
    echo "  sudo systemctl stop risuai"
    echo "  sudo systemctl status risuai"
    echo "  sudo journalctl -u risuai -f"
    echo ""
    if [ "$ENABLE_HTTPS" = "1" ]; then
        echo "HTTPS certificate:"
        echo "  $INSTALL_DIR/server/node/ssl/certificate/ca.crt"
        echo "  (import this to your browser/OS to avoid security warnings)"
        echo ""
    fi
}

cleanup() {
    local self
    self=$(readlink -f "$0" 2>/dev/null || echo "$0")
    [ -f "$self" ] && rm -f "$self" 2>/dev/null || true
}

main() {
    echo "RisuAI Autoinstall Shell Script"
    echo ""

    detect_system
    prompt_config

    echo ""
    log "Starting installation..."

    install_deps
    install_nvm
    install_node
    install_pnpm
    if [ "$INSTALL_MODE" = "1" ] && [ -d "$INSTALL_DIR" ]; then
        log "기존 설치 디렉토리 삭제 중..."
        rm -rf "$INSTALL_DIR"
    fi
    clone_risuai
    build_risuai

    setup_tailscale
    setup_cloudflare
    setup_https

    setup_restic
    setup_git_backup

    create_systemd
    create_scripts
    setup_bashrc

    print_done
    cleanup
}

main "$@"
EOF
chmod +x ~/install.sh && echo "Created: ~/install.sh" && echo "Run: sudo bash ~/install.sh"