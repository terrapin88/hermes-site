/**
 * Hermes Chat Widget
 * Self-contained chat component for the Hermes onboarding site.
 * Usage:
 *   <script src="js/chat-widget.js"></script>
 *   <script>HermesChat.init({ endpoint: '/api/webhook' });</script>
 *   // Toggle with: HermesChat.toggle()
 */
(function () {
  'use strict';

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  let config = { endpoint: '/api/webhook' };
  let sessionId = null;
  let isOpen = false;
  let isFirstOpen = true;
  let isSending = false;
  let messages = []; // { role, content }

  // DOM refs
  let root, chatWindow, msgArea, inputField, sendBtn, typingEl;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  function uid() {
    return 'hv-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 9);
  }

  function getSessionId() {
    const key = 'hermes_chat_session';
    let id = localStorage.getItem(key);
    if (!id) {
      id = uid();
      localStorage.setItem(key, id);
    }
    return id;
  }

  function escapeHtml(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }

  // Markdown-lite renderer
  function renderMarkdown(text) {
    // Escape HTML first
    let html = escapeHtml(text);

    // Code blocks (``` ... ```)
    html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, function (_m, _lang, code) {
      return '<pre class="hc-codeblock"><code>' + code.trim() + '</code></pre>';
    });

    // Inline code
    html = html.replace(/`([^`\n]+)`/g, '<code class="hc-inline-code">$1</code>');

    // Bold
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

    // Italic
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

    // Links [text](url)
    html = html.replace(/\[([^\]]+)\]\((https?:\/\/[^\)]+)\)/g,
      '<a href="$2" target="_blank" rel="noopener" class="hc-link">$1</a>');

    // Bare URLs
    html = html.replace(/(^|[\s>])(https?:\/\/[^\s<]+)/g,
      '$1<a href="$2" target="_blank" rel="noopener" class="hc-link">$2</a>');

    // Line breaks
    html = html.replace(/\n/g, '<br>');

    return html;
  }

  // ---------------------------------------------------------------------------
  // Styles (injected once)
  // ---------------------------------------------------------------------------
  function injectStyles() {
    if (document.getElementById('hermes-chat-styles')) return;
    const style = document.createElement('style');
    style.id = 'hermes-chat-styles';
    style.textContent = `
      /* Root */
      #hermes-chat-root {
        --hc-gold: #c9a84c;
        --hc-gold-hover: #b8963e;
        --hc-gold-dim: #d4a847;
        --hc-bg: #faf8f4;
        --hc-bg-header: #ede8df;
        --hc-bg-input: #f5f2ec;
        --hc-text: #2a2520;
        --hc-text-dim: #8a7e72;
        --hc-text-light: #6b6058;
        --hc-border: #e2dbd0;
        --hc-radius: 14px;
        --hc-shadow: 0 8px 40px rgba(42, 37, 32, 0.15), 0 2px 12px rgba(42, 37, 32, 0.08);
        position: fixed;
        bottom: 24px;
        right: 24px;
        z-index: 99999;
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, sans-serif;
        font-size: 14px;
        line-height: 1.5;
        color: var(--hc-text);
      }

      /* Chat window */
      #hermes-chat-window {
        width: 380px;
        max-height: 540px;
        background: var(--hc-bg);
        border: 1px solid var(--hc-border);
        border-top: 2px solid var(--hc-gold);
        border-radius: var(--hc-radius);
        box-shadow: var(--hc-shadow);
        display: flex;
        flex-direction: column;
        overflow: hidden;
        transform: translateY(20px) scale(0.95);
        opacity: 0;
        pointer-events: none;
        transition: transform 0.3s cubic-bezier(0.4,0,0.2,1),
                    opacity 0.25s ease;
      }
      #hermes-chat-window.hc-open {
        transform: translateY(0) scale(1);
        opacity: 1;
        pointer-events: auto;
      }

      /* Header */
      .hc-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 14px 16px;
        background: var(--hc-bg-header);
        border-bottom: 1px solid var(--hc-border);
        flex-shrink: 0;
      }
      .hc-header-title {
        display: flex;
        align-items: center;
        gap: 8px;
        font-weight: 600;
        font-size: 15px;
        color: var(--hc-text);
        letter-spacing: 0.02em;
      }
      .hc-header-icon {
        font-size: 18px;
        line-height: 1;
        color: var(--hc-gold);
      }
      .hc-close-btn {
        background: none;
        border: none;
        color: var(--hc-text-dim);
        cursor: pointer;
        padding: 4px;
        border-radius: 6px;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: color 0.15s, background 0.15s;
      }
      .hc-close-btn:hover {
        color: var(--hc-text);
        background: rgba(42, 37, 32, 0.07);
      }

      /* Messages area */
      .hc-messages {
        flex: 1;
        overflow-y: auto;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        min-height: 280px;
        max-height: 380px;
        background: var(--hc-bg);
        scrollbar-width: thin;
        scrollbar-color: rgba(201, 168, 76, 0.3) transparent;
      }
      .hc-messages::-webkit-scrollbar { width: 5px; }
      .hc-messages::-webkit-scrollbar-track { background: transparent; }
      .hc-messages::-webkit-scrollbar-thumb {
        background: rgba(201, 168, 76, 0.3);
        border-radius: 4px;
      }
      .hc-messages::-webkit-scrollbar-thumb:hover {
        background: rgba(201, 168, 76, 0.5);
      }

      /* Message bubbles */
      .hc-msg {
        max-width: 85%;
        padding: 10px 14px;
        border-radius: 16px;
        word-wrap: break-word;
        animation: hcFadeIn 0.25s ease;
        font-size: 14px;
        line-height: 1.55;
      }
      .hc-msg-user {
        align-self: flex-end;
        background: var(--hc-gold);
        color: var(--hc-text);
        border-bottom-right-radius: 4px;
        box-shadow: 0 1px 4px rgba(201, 168, 76, 0.25);
      }
      .hc-msg-assistant {
        align-self: flex-start;
        background: #ffffff;
        color: var(--hc-text);
        border-bottom-left-radius: 4px;
        box-shadow: 0 1px 6px rgba(42, 37, 32, 0.08);
      }
      .hc-msg a.hc-link {
        color: var(--hc-gold-hover);
        text-decoration: underline;
        text-decoration-color: rgba(184, 150, 62, 0.4);
        text-underline-offset: 2px;
      }
      .hc-msg a.hc-link:hover {
        text-decoration-color: var(--hc-gold-hover);
      }
      .hc-msg-user a.hc-link {
        color: var(--hc-text);
        text-decoration-color: rgba(42, 37, 32, 0.4);
      }
      .hc-msg pre.hc-codeblock {
        background: #f0ece4;
        padding: 8px 10px;
        border-radius: 6px;
        overflow-x: auto;
        margin: 6px 0;
        font-size: 12px;
        line-height: 1.4;
        border: 1px solid var(--hc-border);
      }
      .hc-msg-user pre.hc-codeblock {
        background: rgba(42, 37, 32, 0.1);
        border-color: rgba(42, 37, 32, 0.15);
      }
      .hc-msg code.hc-inline-code {
        background: #ede8df;
        padding: 1px 5px;
        border-radius: 3px;
        font-size: 13px;
      }
      .hc-msg-user code.hc-inline-code {
        background: rgba(42, 37, 32, 0.1);
      }

      /* Typing indicator */
      .hc-typing {
        align-self: flex-start;
        display: none;
        gap: 4px;
        padding: 12px 18px;
        background: #ffffff;
        border-radius: 16px;
        border-bottom-left-radius: 4px;
        box-shadow: 0 1px 6px rgba(42, 37, 32, 0.08);
      }
      .hc-typing.hc-visible { display: flex; }
      .hc-typing-dot {
        width: 7px;
        height: 7px;
        background: var(--hc-gold);
        border-radius: 50%;
        animation: hcBounce 1.2s infinite ease-in-out;
      }
      .hc-typing-dot:nth-child(2) { animation-delay: 0.15s; }
      .hc-typing-dot:nth-child(3) { animation-delay: 0.3s; }

      /* Input bar */
      .hc-input-bar {
        display: flex;
        align-items: center;
        padding: 10px 12px;
        background: var(--hc-bg-input);
        border-top: 1px solid var(--hc-border);
        gap: 8px;
        flex-shrink: 0;
      }
      .hc-input {
        flex: 1;
        background: #ffffff;
        border: 1px solid var(--hc-border);
        border-radius: 20px;
        padding: 9px 16px;
        color: var(--hc-text);
        font-size: 14px;
        font-family: inherit;
        outline: none;
        transition: border-color 0.2s, box-shadow 0.2s;
      }
      .hc-input::placeholder { color: var(--hc-text-dim); }
      .hc-input:focus {
        border-color: var(--hc-gold);
        box-shadow: 0 0 0 3px rgba(201, 168, 76, 0.15);
      }
      .hc-send-btn {
        width: 36px;
        height: 36px;
        border-radius: 50%;
        border: none;
        background: var(--hc-gold);
        color: #ffffff;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition: background 0.15s, transform 0.1s;
      }
      .hc-send-btn:hover { background: var(--hc-gold-hover); }
      .hc-send-btn:active { transform: scale(0.92); }
      .hc-send-btn:disabled {
        opacity: 0.4;
        cursor: default;
        transform: none;
      }

      /* Animations */
      @keyframes hcFadeIn {
        from { opacity: 0; transform: translateY(6px); }
        to   { opacity: 1; transform: translateY(0); }
      }
      @keyframes hcBounce {
        0%, 60%, 100% { transform: translateY(0); }
        30% { transform: translateY(-5px); }
      }

      /* Mobile responsive */
      @media (max-width: 480px) {
        #hermes-chat-root {
          bottom: 0;
          right: 0;
          left: 0;
        }
        #hermes-chat-window {
          width: 100%;
          max-height: 100dvh;
          border-radius: 16px 16px 0 0;
        }
        .hc-messages { max-height: 60dvh; }
      }
    `;
    document.head.appendChild(style);
  }

  // ---------------------------------------------------------------------------
  // DOM construction
  // ---------------------------------------------------------------------------
  function buildDOM() {
    root = document.createElement('div');
    root.id = 'hermes-chat-root';

    root.innerHTML = `
      <div id="hermes-chat-window">
        <div class="hc-header">
          <span class="hc-header-title">
            <span class="hc-header-icon">☤</span>
            Hermes
          </span>
          <button class="hc-close-btn" aria-label="Close chat">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>
        <div class="hc-messages"></div>
        <div class="hc-typing">
          <div class="hc-typing-dot"></div>
          <div class="hc-typing-dot"></div>
          <div class="hc-typing-dot"></div>
        </div>
        <div class="hc-input-bar">
          <input class="hc-input" type="text" placeholder="Ask about Hermes setup..." autocomplete="off" />
          <button class="hc-send-btn" aria-label="Send message">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
            </svg>
          </button>
        </div>
      </div>
    `;

    document.body.appendChild(root);

    chatWindow = root.querySelector('#hermes-chat-window');
    msgArea = root.querySelector('.hc-messages');
    typingEl = root.querySelector('.hc-typing');
    inputField = root.querySelector('.hc-input');
    sendBtn = root.querySelector('.hc-send-btn');

    // Close button
    root.querySelector('.hc-close-btn').addEventListener('click', function () {
      toggle(false);
    });

    // Send on click
    sendBtn.addEventListener('click', function () {
      handleSend();
    });

    // Send on Enter
    inputField.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------
  function appendMessage(role, content) {
    messages.push({ role: role, content: content });
    const div = document.createElement('div');
    div.className = 'hc-msg hc-msg-' + role;
    div.innerHTML = renderMarkdown(content);
    msgArea.appendChild(div);
    scrollToBottom();
  }

  function scrollToBottom() {
    requestAnimationFrame(function () {
      msgArea.scrollTop = msgArea.scrollHeight;
    });
  }

  function showTyping() {
    typingEl.classList.add('hc-visible');
    // Move typing indicator into msg area for proper scroll
    msgArea.appendChild(typingEl);
    scrollToBottom();
  }

  function hideTyping() {
    typingEl.classList.remove('hc-visible');
  }

  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------
  async function sendToAPI(userContent) {
    if (isSending) return;
    isSending = true;
    sendBtn.disabled = true;
    showTyping();

    // Build the messages payload — send recent context (last 20 messages)
    var recentMessages = messages.slice(-20);

    try {
      var resp = await fetch(config.endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: sessionId,
          messages: recentMessages
        })
      });

      if (!resp.ok) throw new Error('HTTP ' + resp.status);

      var data = await resp.json();
      hideTyping();

      if (data.response && data.response.content) {
        appendMessage('assistant', data.response.content);
      } else if (typeof data.response === 'string') {
        appendMessage('assistant', data.response);
      }
    } catch (err) {
      hideTyping();
      appendMessage('assistant', 'Sorry, I couldn\'t connect right now. Please try again in a moment.');
      console.error('[HermesChat] API error:', err);
    } finally {
      isSending = false;
      sendBtn.disabled = false;
      inputField.focus();
    }
  }

  // ---------------------------------------------------------------------------
  // User input
  // ---------------------------------------------------------------------------
  function handleSend() {
    var text = inputField.value.trim();
    if (!text || isSending) return;
    inputField.value = '';
    appendMessage('user', text);
    sendToAPI(text);
  }

  // ---------------------------------------------------------------------------
  // Toggle
  // ---------------------------------------------------------------------------
  function toggle(forceState) {
    if (typeof forceState === 'boolean') {
      isOpen = forceState;
    } else {
      isOpen = !isOpen;
    }

    if (isOpen) {
      chatWindow.classList.add('hc-open');
      inputField.focus();
      if (isFirstOpen) {
        isFirstOpen = false;
        // Auto-send greeting
        appendMessage('user', 'hi');
        sendToAPI('hi');
      }
    } else {
      chatWindow.classList.remove('hc-open');
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------
  window.HermesChat = {
    init: function (userConfig) {
      if (userConfig) {
        if (userConfig.endpoint) config.endpoint = userConfig.endpoint;
      }
      sessionId = getSessionId();
      injectStyles();

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', buildDOM);
      } else {
        buildDOM();
      }
    },

    toggle: function (forceState) {
      toggle(forceState);
    },

    open: function () { toggle(true); },
    close: function () { toggle(false); },

    /** Send a message programmatically */
    send: function (text) {
      if (!text) return;
      appendMessage('user', text);
      sendToAPI(text);
    },

    /** Reset the conversation */
    reset: function () {
      messages = [];
      isFirstOpen = true;
      sessionId = uid();
      localStorage.setItem('hermes_chat_session', sessionId);
      if (msgArea) msgArea.innerHTML = '';
    }
  };
})();
