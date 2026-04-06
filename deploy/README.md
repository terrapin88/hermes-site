# Hermes Onboarding Site — Deployment Guide

## Architecture

```
  Browser
    │
    ▼
┌────────────────────┐
│   Caddy (port 80/443)   │
│   - Static files   │
│   - Auto HTTPS     │
│   - CORS headers   │
└────────┬───────────┘
         │ /api/* → strip prefix → proxy
         ▼
┌────────────────────┐
│  Hermes Agent      │
│  (port 8644)       │
│  - Webhook API     │
│  - Chat sessions   │
└────────────────────┘
```

## Quick Start — DigitalOcean Droplet

### 1. Create the Droplet

1. Sign up at [digitalocean.com](https://www.digitalocean.com/try) ($200 free credit)
2. Create a Droplet:
   - **Marketplace** → search **Docker** → select "Docker on Ubuntu 24.04"
   - **Plan**: Basic $12/mo (1 vCPU, 2GB RAM, 50GB SSD)
   - **Region**: closest to your audience
   - **Authentication**: SSH key (recommended) or password
3. Note your Droplet's IP address

### 2. Point your domain

Add an **A record** in your DNS provider:
```
Type: A
Name: @ (or subdomain like "chat")
Value: <your-droplet-ip>
TTL: 300
```

### 3. Deploy

SSH into your Droplet and run:

```bash
# Clone the project
ssh root@<your-droplet-ip>
git clone https://github.com/YOUR_USER/hermes-site.git
cd hermes-site/deploy

# Configure
cp .env.example .env
nano .env   # Set DOMAIN and API keys

# Deploy
bash setup.sh
```

That's it. Caddy auto-provisions HTTPS via Let's Encrypt.

### 4. Verify

- Visit `https://yourdomain.com` — landing page should load
- Click the chat bubble — concierge should respond
- Check health: `curl https://yourdomain.com/api/health`

## Files

```
hermes-site/
├── index.html                  # Landing page
├── js/
│   └── chat-widget.js          # Chat concierge widget
└── deploy/
    ├── setup.sh                # One-click deploy script
    ├── docker-compose.yml      # Container orchestration
    ├── Dockerfile.hermes       # Hermes agent container
    ├── Caddyfile               # Web server / reverse proxy config
    ├── concierge-prompt.md     # Agent system prompt
    ├── .env.example            # Environment template
    └── README.md               # This file
```

## Configuration

### .env variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DOMAIN` | Yes | Your domain (e.g., `hermes.yourdomain.com`) |
| `ANTHROPIC_API_KEY` | One of these | Anthropic API key |
| `NOUS_API_KEY` | One of these | Nous Portal API key |
| `OPENAI_API_KEY` | One of these | OpenAI API key |
| `HERMES_MODEL` | No | Override default model |
| `HERMES_PROVIDER` | No | Override default provider |

### Switching from Anthropic to Nous Portal

When Anthropic credits run out, edit `.env`:
```bash
# Comment out Anthropic
# ANTHROPIC_API_KEY=sk-ant-...

# Uncomment Nous
NOUS_API_KEY=sk-your-nous-key

# Optionally set provider/model
HERMES_PROVIDER=nous
HERMES_MODEL=hermes-3-llama-3.1-70b
```

Then restart:
```bash
docker compose restart hermes
```

## Operations

```bash
# View logs
docker compose logs -f              # all services
docker compose logs -f hermes       # agent only
docker compose logs -f caddy        # web server only

# Restart
docker compose restart              # all
docker compose restart hermes       # agent only

# Update agent
docker compose build --no-cache hermes
docker compose up -d hermes

# Stop everything
docker compose down

# Full rebuild
docker compose down
docker compose up -d --build
```

## Local Development

For local testing without a domain:

```bash
# Leave DOMAIN as localhost in .env
DOMAIN=localhost

# Start
docker compose up -d

# Visit http://localhost
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Chat widget says "connection error" | Check: `docker compose logs hermes` |
| Caddy won't start | Check DOMAIN is correct, DNS is pointed, ports 80/443 are open |
| No HTTPS certificate | Caddy needs ports 80+443 open AND valid DNS pointing to server |
| Agent responds slowly | Normal for first request (model loading). Subsequent requests faster. |
| Out of API credits | Switch provider in .env, restart hermes container |

## Cost

- **DigitalOcean Droplet**: ~$12/mo (2GB RAM)
- **Domain**: ~$10-15/year
- **AI API credits**: varies by usage
- **Total**: ~$13-15/mo + API costs
