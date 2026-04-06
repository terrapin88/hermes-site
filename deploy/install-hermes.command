#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Hermes Agent — One-Click Installer
#  Your personal AI assistant, ready in minutes.
# ═══════════════════════════════════════════════════════════════
clear

CYAN='\033[0;36m'
GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${GOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${GOLD}          ⚕  Hermes Agent Installer${NC}"
echo -e "${GOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  This will set up your personal AI assistant and"
echo -e "  connect it to Telegram so you can chat from anywhere."
echo ""
echo -e "  ${CYAN}What happens next:${NC}"
echo -e "    1. Install Hermes Agent"
echo -e "    2. Connect to Nous AI (free to start)"
echo -e "    3. Create your Telegram bot (30 seconds)"
echo -e "    4. Start chatting!"
echo ""
echo -e "${GOLD}═══════════════════════════════════════════════════════${NC}"
echo ""

# ── Step 1: Install Hermes ───────────────────────────────────
echo -e "${CYAN}[1/4]${NC} Installing Hermes Agent..."
echo ""

if command -v hermes &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Hermes is already installed!"
    hermes --version 2>/dev/null || true
else
    echo "  Downloading and installing (this takes 1-2 minutes)..."
    echo ""
    curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup 2>&1 | while IFS= read -r line; do
        echo "    $line"
    done

    # Source the updated PATH
    export PATH="$HOME/.local/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"
    
    if ! command -v hermes &>/dev/null; then
        echo -e "  ${RED}✗${NC} Installation failed. Please try:"
        echo "    curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
        echo ""
        read -p "Press Enter to exit..."
        exit 1
    fi
    echo ""
    echo -e "  ${GREEN}✓${NC} Hermes installed!"
fi

echo ""

# ── Step 2: Configure Nous Portal ────────────────────────────
echo -e "${CYAN}[2/4]${NC} Setting up Nous Portal (your AI brain)..."
echo ""

HERMES_HOME="$HOME/.hermes"
ENV_FILE="$HERMES_HOME/.env"
CONFIG_FILE="$HERMES_HOME/config.yaml"

mkdir -p "$HERMES_HOME"

# Check if already configured
if grep -q "NOUS_API_KEY=sk-" "$ENV_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Nous Portal already configured!"
else
    echo -e "  Nous Portal provides the AI models that power Hermes."
    echo -e "  Sign up free at: ${BOLD}https://portal.nousresearch.com${NC}"
    echo ""
    
    # Open signup page
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "https://portal.nousresearch.com" 2>/dev/null &
    elif command -v xdg-open &>/dev/null; then
        xdg-open "https://portal.nousresearch.com" 2>/dev/null &
    fi
    
    echo -e "  ${GOLD}→ A browser window should have opened.${NC}"
    echo -e "  ${GOLD}  Sign up, then copy your API key from the dashboard.${NC}"
    echo ""
    
    while true; do
        read -p "  Paste your Nous Portal API key: " NOUS_KEY
        if [[ "$NOUS_KEY" == sk-* ]] && [[ ${#NOUS_KEY} -gt 10 ]]; then
            break
        fi
        echo -e "  ${RED}  That doesn't look right. It should start with 'sk-'${NC}"
    done
    
    # Save to .env
    touch "$ENV_FILE"
    if grep -q "NOUS_API_KEY" "$ENV_FILE" 2>/dev/null; then
        sed -i.bak "s|^NOUS_API_KEY=.*|NOUS_API_KEY=$NOUS_KEY|" "$ENV_FILE"
    else
        echo "NOUS_API_KEY=$NOUS_KEY" >> "$ENV_FILE"
    fi
    
    echo ""
    echo -e "  ${GREEN}✓${NC} Nous Portal connected!"
fi

# Set Nous as default provider in config
if [ -f "$CONFIG_FILE" ]; then
    # Update provider to nous if currently something else
    sed -i.bak 's/^  provider:.*/  provider: nous/' "$CONFIG_FILE" 2>/dev/null || true
fi

echo ""

# ── Step 3: Create Telegram Bot ──────────────────────────────
echo -e "${CYAN}[3/4]${NC} Setting up your Telegram bot..."
echo ""

if grep -q "TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null && ! grep -q "TELEGRAM_BOT_TOKEN=$" "$ENV_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Telegram bot already configured!"
else
    echo -e "  You need a Telegram bot token. It takes 30 seconds:"
    echo ""
    echo -e "  ${BOLD}Here's what to do:${NC}"
    echo -e "    1. Telegram will open to @BotFather"
    echo -e "    2. Send:  ${GOLD}/newbot${NC}"
    echo -e "    3. Name it whatever you like (e.g. 'My Hermes')"
    echo -e "    4. Give it a username ending in 'bot' (e.g. 'myhermes_bot')"
    echo -e "    5. BotFather gives you a token — copy it"
    echo ""
    
    sleep 2
    
    # Open BotFather
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "https://t.me/BotFather" 2>/dev/null &
    elif command -v xdg-open &>/dev/null; then
        xdg-open "https://t.me/BotFather" 2>/dev/null &
    fi
    
    echo -e "  ${GOLD}→ Telegram should have opened to @BotFather.${NC}"
    echo ""
    
    while true; do
        read -p "  Paste your bot token here: " BOT_TOKEN
        if [[ "$BOT_TOKEN" == *":"* ]] && [[ ${#BOT_TOKEN} -gt 30 ]]; then
            break
        fi
        echo -e "  ${RED}  That doesn't look like a bot token. It should look like: 123456789:ABCdef...${NC}"
    done
    
    # Save token
    if grep -q "TELEGRAM_BOT_TOKEN" "$ENV_FILE" 2>/dev/null; then
        sed -i.bak "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=$BOT_TOKEN|" "$ENV_FILE"
    else
        echo "TELEGRAM_BOT_TOKEN=$BOT_TOKEN" >> "$ENV_FILE"
    fi
    
    echo ""
    echo -e "  ${GREEN}✓${NC} Telegram bot configured!"
fi

echo ""

# ── Step 4: Start Gateway & Open Telegram ────────────────────
echo -e "${CYAN}[4/4]${NC} Starting Hermes..."
echo ""

# Enable telegram in config
if [ -f "$CONFIG_FILE" ]; then
    # Ensure gateway telegram is enabled
    python3 -c "
import yaml, sys
config_path = '$CONFIG_FILE'
try:
    with open(config_path) as f:
        config = yaml.safe_load(f) or {}
    gw = config.setdefault('gateway', {})
    tg = gw.setdefault('telegram', {})
    tg['enabled'] = True
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
except Exception as e:
    pass
" 2>/dev/null || true
fi

# Install and start gateway service
echo "  Starting the Hermes gateway service..."
hermes gateway install 2>/dev/null || true
hermes gateway start 2>/dev/null || true

sleep 3

# Check if it's running
if hermes gateway status 2>/dev/null | grep -qi "running"; then
    echo -e "  ${GREEN}✓${NC} Hermes gateway is running!"
else
    echo -e "  ${GOLD}  Starting gateway in background...${NC}"
    nohup hermes gateway run &>/dev/null &
    sleep 2
fi

echo ""

# Extract bot username from token for the deep link
BOT_TOKEN=$(grep "TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2)

echo -e "${GOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}"
echo -e "  ✓  Hermes is LIVE!${NC}"
echo -e "${GOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Open Telegram and message your bot to start chatting."
echo -e "  Hermes is now your personal AI assistant!"
echo ""
echo -e "  ${CYAN}Quick tips:${NC}"
echo -e "    • Send any message to chat with Hermes"
echo -e "    • Hermes can search the web, write code, manage files"
echo -e "    • Say 'help' for a list of things Hermes can do"
echo ""
echo -e "  ${CYAN}Useful commands (in this terminal):${NC}"
echo -e "    hermes              — chat with Hermes in terminal"
echo -e "    hermes gateway status — check if Telegram bot is running"
echo -e "    hermes gateway stop   — stop the Telegram bot"
echo ""
echo -e "${GOLD}═══════════════════════════════════════════════════════${NC}"
echo ""

# Try to open the user's bot in Telegram
echo -e "  Opening your bot in Telegram..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Try to get bot info to find username
    BOT_INFO=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
    BOT_USERNAME=$(echo "$BOT_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',{}).get('username',''))" 2>/dev/null)
    
    if [ -n "$BOT_USERNAME" ]; then
        open "https://t.me/$BOT_USERNAME" 2>/dev/null
        echo -e "  ${GREEN}→ Opening @$BOT_USERNAME in Telegram${NC}"
    else
        echo -e "  ${GOLD}  Find your bot in Telegram and send it a message!${NC}"
    fi
fi

echo ""
read -p "Press Enter to close this window..."
