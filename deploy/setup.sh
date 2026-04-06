#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  Hermes Onboarding Site — DigitalOcean Droplet Setup Script
# ═══════════════════════════════════════════════════════════════
#
#  Run this on a fresh DigitalOcean Docker Droplet:
#    curl -sSL https://raw.githubusercontent.com/YOU/hermes-site/main/deploy/setup.sh | bash
#  Or after cloning:
#    cd ~/hermes-site/deploy && bash setup.sh
#

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hermes Onboarding Site — Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Check prerequisites ───────────────────────────────────
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker not found. Use the DigitalOcean Docker 1-Click Droplet."
command -v docker compose >/dev/null 2>&1 || fail "Docker Compose not found."

ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+')"
ok "Docker Compose available"

# ── 2. Determine project directory ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"
PROJECT_DIR="$(dirname "$DEPLOY_DIR")"

if [[ ! -f "$DEPLOY_DIR/docker-compose.yml" ]]; then
    fail "docker-compose.yml not found in $DEPLOY_DIR"
fi

info "Project directory: $PROJECT_DIR"
info "Deploy directory:  $DEPLOY_DIR"

# ── 3. Create .env if it doesn't exist ───────────────────────
if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
    warn ".env file not found. Creating from template..."

    if [[ -f "$DEPLOY_DIR/.env.example" ]]; then
        cp "$DEPLOY_DIR/.env.example" "$DEPLOY_DIR/.env"
    else
        cat > "$DEPLOY_DIR/.env" <<'ENVEOF'
DOMAIN=localhost
ANTHROPIC_API_KEY=
NOUS_API_KEY=
HERMES_MODEL=
HERMES_PROVIDER=
ENVEOF
    fi

    echo ""
    warn "╔══════════════════════════════════════════════════╗"
    warn "║  IMPORTANT: Edit .env with your actual values!  ║"
    warn "║                                                  ║"
    warn "║  nano $DEPLOY_DIR/.env          ║"
    warn "║                                                  ║"
    warn "║  At minimum set:                                 ║"
    warn "║    DOMAIN=yourdomain.com                         ║"
    warn "║    ANTHROPIC_API_KEY=sk-ant-...                  ║"
    warn "║    (or NOUS_API_KEY for Nous Portal)             ║"
    warn "╚══════════════════════════════════════════════════╝"
    echo ""
    read -p "Press Enter after editing .env (or Ctrl+C to abort)..."
fi

# ── 4. Validate .env ─────────────────────────────────────────
info "Validating .env..."
source "$DEPLOY_DIR/.env"

if [[ "${DOMAIN:-localhost}" == "localhost" ]]; then
    warn "DOMAIN is set to 'localhost' — running in local/dev mode (no HTTPS)"
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${NOUS_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
    fail "No API key set. Set at least one of: ANTHROPIC_API_KEY, NOUS_API_KEY, OPENAI_API_KEY"
fi

ok ".env looks good"

# ── 5. Configure firewall ────────────────────────────────────
info "Configuring firewall (UFW)..."

if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp   >/dev/null 2>&1 || true
    ufw allow 443/tcp  >/dev/null 2>&1 || true
    ufw allow 443/udp  >/dev/null 2>&1 || true  # HTTP/3
    ufw allow 22/tcp   >/dev/null 2>&1 || true  # SSH
    ufw --force enable  >/dev/null 2>&1 || true
    ok "Firewall configured (80, 443, 22)"
else
    warn "UFW not found — make sure ports 80/443 are open in your DO firewall"
fi

# ── 6. Build and start ───────────────────────────────────────
info "Building Hermes agent container..."
cd "$DEPLOY_DIR"
docker compose build --no-cache hermes

info "Starting services..."
docker compose up -d

echo ""
info "Waiting for services to come up..."
sleep 5

# ── 7. Health check ──────────────────────────────────────────
info "Running health checks..."

if docker compose ps | grep -q "running"; then
    ok "Containers are running"
else
    fail "Some containers failed to start. Run: docker compose logs"
fi

# Check if Caddy is responding
if curl -sf http://localhost/health >/dev/null 2>&1 || curl -sf http://localhost/ >/dev/null 2>&1; then
    ok "Web server is responding"
else
    warn "Web server not responding yet — may still be starting up"
fi

# ── 8. Summary ────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo -e "  ${GREEN}Hermes Onboarding Site is LIVE!${NC}"
echo "═══════════════════════════════════════════════════"
echo ""

if [[ "${DOMAIN:-localhost}" != "localhost" ]]; then
    echo "  Site:      https://${DOMAIN}"
    echo "  API:       https://${DOMAIN}/api/webhook"
    echo "  Health:    https://${DOMAIN}/api/health"
else
    echo "  Site:      http://localhost"
    echo "  API:       http://localhost/api/webhook"
    echo "  Health:    http://localhost/api/health"
fi

echo ""
echo "  Useful commands:"
echo "    docker compose logs -f          # follow logs"
echo "    docker compose logs hermes      # agent logs only"
echo "    docker compose restart          # restart all"
echo "    docker compose down             # stop all"
echo "    docker compose up -d --build    # rebuild & restart"
echo ""
echo "  DNS: Point your domain's A record to this server's IP:"
echo "    $(curl -sf ifconfig.me || echo '<your-droplet-ip>')"
echo ""
