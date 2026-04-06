"""
Hermes Concierge — Lightweight webhook server for the onboarding chat widget.

Accepts POST /webhook with chat messages, calls the LLM via OpenAI-compatible API,
and returns the assistant's response. Maintains per-session conversation history.

No dependency on hermes gateway — just openai + flask.
"""

import os
import uuid
import time
import threading
from flask import Flask, request, jsonify

import anthropic
from openai import OpenAI
from pathlib import Path

app = Flask(__name__)

# ── Configuration ────────────────────────────────────────────
SYSTEM_PROMPT_PATH = os.environ.get(
    "CONCIERGE_PROMPT", "/home/hermes/.hermes/concierge-prompt.md"
)
MODEL = os.environ.get("HERMES_MODEL", "") or "claude-opus-4-6"
PROVIDER = os.environ.get("HERMES_PROVIDER", "anthropic")
MAX_HISTORY = 40  # max messages per session to keep


def get_provider_and_key():
    """Determine which provider and API key to use."""
    provider_key_map = {
        "anthropic": "ANTHROPIC_API_KEY",
        "nous": "NOUS_API_KEY",
        "openai": "OPENAI_API_KEY",
        "openrouter": "OPENROUTER_API_KEY",
    }

    # Try configured provider first
    key_env = provider_key_map.get(PROVIDER, "ANTHROPIC_API_KEY")
    api_key = os.environ.get(key_env, "")
    if api_key:
        return PROVIDER, api_key

    # Fallback: try all providers
    for prov, env_var in provider_key_map.items():
        api_key = os.environ.get(env_var, "")
        if api_key:
            return prov, api_key

    raise RuntimeError("No API key found. Set ANTHROPIC_API_KEY, NOUS_API_KEY, or OPENAI_API_KEY.")


def load_system_prompt():
    """Load the concierge system prompt from file."""
    try:
        return Path(SYSTEM_PROMPT_PATH).read_text().strip()
    except FileNotFoundError:
        return "You are Hermes, a helpful AI assistant created by Nous Research. Help users learn about and set up Hermes Agent."


# ── Session Store ────────────────────────────────────────────
sessions = {}
session_lock = threading.Lock()


def cleanup_old_sessions():
    """Remove sessions older than 1 hour."""
    cutoff = time.time() - 3600
    with session_lock:
        expired = [sid for sid, data in sessions.items() if data["last_active"] < cutoff]
        for sid in expired:
            del sessions[sid]


# ── Routes ───────────────────────────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/webhook", methods=["POST"])
def webhook():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400

    session_id = data.get("session_id") or str(uuid.uuid4())
    messages = data.get("messages", [])

    if not messages:
        return jsonify({"error": "No messages provided"}), 400

    # Get or create session
    with session_lock:
        if session_id not in sessions:
            sessions[session_id] = {"messages": [], "last_active": time.time()}
        session = sessions[session_id]
        session["last_active"] = time.time()

        # Append new user messages
        for msg in messages:
            if msg.get("role") and msg.get("content"):
                session["messages"].append({
                    "role": msg["role"],
                    "content": msg["content"]
                })

        # Trim to max history
        if len(session["messages"]) > MAX_HISTORY:
            session["messages"] = session["messages"][-MAX_HISTORY:]

        # Build full message list with system prompt
        full_messages = [
            {"role": "system", "content": load_system_prompt()}
        ] + list(session["messages"])

    # Call LLM
    try:
        provider, api_key = get_provider_and_key()

        if provider == "anthropic":
            client = anthropic.Anthropic(api_key=api_key)
            # Anthropic wants system prompt separate, not in messages
            chat_messages = [m for m in full_messages if m["role"] != "system"]
            response = client.messages.create(
                model=MODEL,
                system=load_system_prompt(),
                messages=chat_messages,
                max_tokens=2048,
                temperature=0.7,
            )
            assistant_content = response.content[0].text
        else:
            # OpenAI-compatible providers (nous, openai, openrouter)
            base_urls = {
                "nous": "https://inference-api.nousresearch.com/v1",
                "openai": "https://api.openai.com/v1",
                "openrouter": "https://openrouter.ai/api/v1",
            }
            client = OpenAI(
                base_url=base_urls.get(provider, base_urls["openai"]),
                api_key=api_key,
            )
            response = client.chat.completions.create(
                model=MODEL,
                messages=full_messages,
                max_tokens=2048,
                temperature=0.7,
            )
            assistant_content = response.choices[0].message.content
    except Exception as e:
        app.logger.error(f"LLM error: {e}")
        assistant_content = "I'm having a moment — could you try again in a few seconds?"

    # Store assistant response
    with session_lock:
        session["messages"].append({
            "role": "assistant",
            "content": assistant_content
        })

    # Periodic cleanup
    if len(sessions) > 100:
        cleanup_old_sessions()

    return jsonify({
        "session_id": session_id,
        "response": {
            "role": "assistant",
            "content": assistant_content
        }
    })


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8644))
    app.run(host="0.0.0.0", port=port)
