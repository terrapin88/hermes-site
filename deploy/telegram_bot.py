"""
Hermes Public Concierge — Telegram Bot

A public-facing Telegram bot that guides users through Hermes Agent,
answers questions, and funnels them toward Nous Research products.
Uses the concierge system prompt for personality.
"""

import os
import logging
import time
import threading
from pathlib import Path
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

import anthropic
from openai import OpenAI

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ── Configuration ────────────────────────────────────────────
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
_raw_model = os.environ.get("HERMES_MODEL", "")
# Default model based on provider
_default_models = {
    "anthropic": "claude-opus-4-6",
    "nous": "NousResearch/Hermes-4-70B",
    "openai": "gpt-4o",
}
PROVIDER = os.environ.get("HERMES_PROVIDER", "") or "anthropic"
MODEL = _raw_model or _default_models.get(PROVIDER, "NousResearch/Hermes-4-70B")
MAX_HISTORY = 30
SYSTEM_PROMPT_PATH = os.environ.get(
    "CONCIERGE_PROMPT", "/app/concierge-prompt.md"
)


def load_system_prompt():
    """Load the concierge system prompt."""
    try:
        return Path(SYSTEM_PROMPT_PATH).read_text().strip()
    except FileNotFoundError:
        return (
            "You are Hermes, a friendly AI assistant created by Nous Research. "
            "You help people learn about and set up Hermes Agent — a free, open-source "
            "personal AI assistant. Be warm, approachable, and enthusiastic. "
            "Guide users toward installing Hermes and using Nous Research products."
        )


# ── Session Store ────────────────────────────────────────────
sessions = {}
session_lock = threading.Lock()


def cleanup_old_sessions():
    """Remove sessions older than 2 hours."""
    cutoff = time.time() - 7200
    with session_lock:
        expired = [sid for sid, data in sessions.items() if data["last_active"] < cutoff]
        for sid in expired:
            del sessions[sid]


def get_session(chat_id):
    """Get or create a session for a chat."""
    sid = str(chat_id)
    with session_lock:
        if sid not in sessions:
            sessions[sid] = {"messages": [], "last_active": time.time()}
        sessions[sid]["last_active"] = time.time()
        return sessions[sid]


# ── LLM Call ─────────────────────────────────────────────────
def call_llm(chat_messages):
    """Call the LLM with conversation history."""
    provider = PROVIDER
    system_prompt = load_system_prompt()

    if provider == "anthropic":
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return "I'm not fully configured yet — the admin needs to add an API key."
        client = anthropic.Anthropic(api_key=api_key)
        response = client.messages.create(
            model=MODEL,
            system=system_prompt,
            messages=chat_messages,
            max_tokens=2048,
            temperature=0.7,
        )
        return response.content[0].text
    else:
        # OpenAI-compatible (nous, openai, openrouter)
        base_urls = {
            "nous": "https://inference-api.nousresearch.com/v1",
            "openai": "https://api.openai.com/v1",
            "openrouter": "https://openrouter.ai/api/v1",
        }
        key_map = {
            "nous": "NOUS_API_KEY",
            "openai": "OPENAI_API_KEY",
            "openrouter": "OPENROUTER_API_KEY",
        }
        api_key = os.environ.get(key_map.get(provider, "NOUS_API_KEY"), "")
        if not api_key:
            return "I'm not fully configured yet — the admin needs to add an API key."

        client = OpenAI(
            base_url=base_urls.get(provider, base_urls["nous"]),
            api_key=api_key,
        )
        full_messages = [{"role": "system", "content": system_prompt}] + chat_messages
        response = client.chat.completions.create(
            model=MODEL,
            messages=full_messages,
            max_tokens=2048,
            temperature=0.7,
        )
        return response.choices[0].message.content


# ── Telegram Handlers ────────────────────────────────────────
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command."""
    session = get_session(update.effective_chat.id)
    session["messages"] = []  # Fresh start

    welcome = call_llm([{"role": "user", "content": "hi"}])
    session["messages"].append({"role": "user", "content": "hi"})
    session["messages"].append({"role": "assistant", "content": welcome})

    await update.message.reply_text(welcome)


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command."""
    await update.message.reply_text(
        "👋 I'm Hermes — your AI assistant!\n\n"
        "Just send me any message and I'll help you out.\n\n"
        "I can:\n"
        "• Answer questions about Hermes Agent\n"
        "• Walk you through installation\n"
        "• Explain what AI agents can do for you\n"
        "• Help with general questions too!\n\n"
        "Type anything to get started."
    )


async def reset_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /reset command."""
    session = get_session(update.effective_chat.id)
    session["messages"] = []
    await update.message.reply_text("🔄 Conversation reset! Send me a message to start fresh.")


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming messages."""
    if not update.message or not update.message.text:
        return

    user_text = update.message.text.strip()
    if not user_text:
        return

    session = get_session(update.effective_chat.id)

    # Add user message
    session["messages"].append({"role": "user", "content": user_text})

    # Trim history
    if len(session["messages"]) > MAX_HISTORY:
        session["messages"] = session["messages"][-MAX_HISTORY:]

    # Show typing indicator
    await update.message.chat.send_action("typing")

    # Call LLM
    try:
        response_text = call_llm(session["messages"])
    except Exception as e:
        logger.error(f"LLM error: {e}")
        response_text = "Sorry, I hit a snag. Try again in a moment!"

    # Store assistant response
    session["messages"].append({"role": "assistant", "content": response_text})

    # Send response (split if too long for Telegram)
    if len(response_text) <= 4096:
        await update.message.reply_text(response_text)
    else:
        # Split on newlines
        chunks = []
        current = ""
        for line in response_text.split("\n"):
            if len(current) + len(line) + 1 > 4000:
                chunks.append(current)
                current = line
            else:
                current = current + "\n" + line if current else line
        if current:
            chunks.append(current)
        for chunk in chunks:
            await update.message.reply_text(chunk)

    # Periodic cleanup
    if len(sessions) > 200:
        cleanup_old_sessions()


# ── Main ─────────────────────────────────────────────────────
def main():
    if not TELEGRAM_TOKEN:
        logger.error("TELEGRAM_BOT_TOKEN not set!")
        return

    logger.info(f"Starting Hermes Public Concierge (model={MODEL}, provider={PROVIDER})")

    app = Application.builder().token(TELEGRAM_TOKEN).build()

    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("reset", reset_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    logger.info("Bot is running! Waiting for messages...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
