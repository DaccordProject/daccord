#!/usr/bin/env python3
"""Firefox WebDriver BiDi helper for Claude Code.

Manages a BiDi session over WebSocket and exposes browser control commands.

Usage:
    python3 firefox_bidi.py <command> [args...]

Commands:
    status                          Check if Firefox remote debugging is available
    tabs                            List open tabs (browsing contexts)
    screenshot [context_id]         Capture screenshot (saves to /tmp/firefox_screenshot.png)
    eval <expression> [context_id]  Evaluate JavaScript in a tab
    navigate <url> [context_id]     Navigate a tab to a URL
    html [selector] [context_id]    Get outerHTML of an element (default: document.body)
    text [selector] [context_id]    Get innerText of an element (default: document.body)
    click <selector> [context_id]   Click an element matching a CSS selector
    type <selector> <text> [ctx]    Type text into an element matching a CSS selector
    title [context_id]              Get page title
    url [context_id]                Get current URL
    reload [context_id]             Reload the page
    back [context_id]               Navigate back
    forward [context_id]            Navigate forward
    new_tab [url]                   Open a new tab (optionally navigate to url)
    close_tab <context_id>          Close a tab
    cookies [context_id]            Get all cookies
    console_log [context_id]        Get recent console.log output
    network [context_id]            Get recent network requests

Port defaults to 9222. Set FIREFOX_BIDI_PORT to override.
"""
import asyncio
import base64
import json
import os
import sys

PORT = int(os.environ.get("FIREFOX_BIDI_PORT", "9222"))
WS_URL = f"ws://localhost:{PORT}/session"
SCREENSHOT_PATH = os.environ.get("FIREFOX_SCREENSHOT_PATH", "/tmp/firefox_screenshot.png")
TIMEOUT = 10

try:
    import websockets
except ImportError:
    print("Error: python3 websockets module required. Install with: pip install websockets", file=sys.stderr)
    sys.exit(1)


async def bidi_session(commands_fn):
    """Connect to Firefox BiDi, manage session lifecycle, run commands."""
    try:
        ws = await websockets.connect(WS_URL)
    except Exception as e:
        print(json.dumps({"error": f"Cannot connect to Firefox on port {PORT}: {e}"}))
        sys.exit(1)

    try:
        msg_id = 0

        async def send(method, params=None):
            nonlocal msg_id
            msg_id += 1
            payload = {"id": msg_id, "method": method, "params": params or {}}
            await ws.send(json.dumps(payload))
            while True:
                raw = await asyncio.wait_for(ws.recv(), timeout=TIMEOUT)
                resp = json.loads(raw)
                # Skip event messages, wait for our response
                if resp.get("id") == msg_id:
                    if resp.get("type") == "error":
                        raise RuntimeError(f"BiDi error: {resp.get('error')}: {resp.get('message')}")
                    return resp.get("result", {})

        # Check status and create session if needed
        status = await send("session.status")
        if status.get("ready", True):
            await send("session.new", {"capabilities": {}})

        result = await commands_fn(send)

        # End session
        try:
            await send("session.end")
        except Exception:
            pass

        return result
    finally:
        await ws.close()


async def get_default_context(send, context_id=None):
    """Get the specified context or the first available tab."""
    if context_id:
        return context_id
    tree = await send("browsingContext.getTree")
    contexts = tree.get("contexts", [])
    if not contexts:
        raise RuntimeError("No browsing contexts (tabs) found")
    return contexts[0]["context"]


async def cmd_status(args):
    async def run(send):
        tree = await send("browsingContext.getTree")
        contexts = tree.get("contexts", [])
        print(json.dumps({
            "status": "connected",
            "port": PORT,
            "tabs": len(contexts),
        }))
    await bidi_session(run)


async def cmd_tabs(args):
    async def run(send):
        tree = await send("browsingContext.getTree")
        tabs = []
        for ctx in tree.get("contexts", []):
            tabs.append({
                "context": ctx["context"],
                "url": ctx["url"],
                "children": len(ctx.get("children", [])),
            })
        print(json.dumps(tabs, indent=2))
    await bidi_session(run)


async def cmd_screenshot(args):
    ctx_id = args[0] if args else None
    output_path = SCREENSHOT_PATH

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("browsingContext.captureScreenshot", {"context": ctx})
        data = base64.b64decode(result["data"])
        with open(output_path, "wb") as f:
            f.write(data)
        print(json.dumps({"path": output_path, "size": len(data)}))
    await bidi_session(run)


async def cmd_eval(args):
    if not args:
        print(json.dumps({"error": "Usage: eval <expression> [context_id]"}))
        sys.exit(1)
    expression = args[0]
    ctx_id = args[1] if len(args) > 1 else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": expression,
            "target": {"context": ctx},
            "awaitPromise": True,
            "serializationOptions": {"maxDomDepth": 0, "maxObjectDepth": 10},
        })
        r = result.get("result", {})
        # Simplify common value types
        if r.get("type") in ("string", "number", "boolean"):
            print(json.dumps({"value": r["value"]}))
        elif r.get("type") == "null":
            print(json.dumps({"value": None}))
        elif r.get("type") == "undefined":
            print(json.dumps({"value": "undefined"}))
        else:
            print(json.dumps({"type": r.get("type"), "value": r.get("value", r)}))
    await bidi_session(run)


async def cmd_navigate(args):
    if not args:
        print(json.dumps({"error": "Usage: navigate <url> [context_id]"}))
        sys.exit(1)
    url = args[0]
    ctx_id = args[1] if len(args) > 1 else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("browsingContext.navigate", {
            "context": ctx, "url": url, "wait": "complete",
        })
        print(json.dumps({"url": result.get("url", url), "navigation": result.get("navigation")}))
    await bidi_session(run)


async def cmd_html(args):
    selector = args[0] if args else "document.body"
    ctx_id = args[1] if len(args) > 1 else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        expr = f'document.querySelector("{selector}")?.outerHTML ?? "Element not found"' if selector != "document.body" else "document.body.outerHTML"
        result = await send("script.evaluate", {
            "expression": expr,
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        val = result.get("result", {}).get("value", "")
        print(val)
    await bidi_session(run)


async def cmd_text(args):
    selector = args[0] if args else "document.body"
    ctx_id = args[1] if len(args) > 1 else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        expr = f'document.querySelector("{selector}")?.innerText ?? "Element not found"' if selector != "document.body" else "document.body.innerText"
        result = await send("script.evaluate", {
            "expression": expr,
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        val = result.get("result", {}).get("value", "")
        print(val)
    await bidi_session(run)


async def cmd_click(args):
    if not args:
        print(json.dumps({"error": "Usage: click <selector> [context_id]"}))
        sys.exit(1)
    selector = args[0]
    ctx_id = args[1] if len(args) > 1 else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": f'''
                (() => {{
                    const el = document.querySelector("{selector}");
                    if (!el) return "Element not found: {selector}";
                    el.click();
                    return "clicked";
                }})()
            ''',
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        val = result.get("result", {}).get("value", "")
        print(json.dumps({"result": val}))
    await bidi_session(run)


async def cmd_type(args):
    if len(args) < 2:
        print(json.dumps({"error": "Usage: type <selector> <text> [context_id]"}))
        sys.exit(1)
    selector = args[0]
    text = args[1]
    ctx_id = args[2] if len(args) > 2 else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        escaped_text = json.dumps(text)
        result = await send("script.evaluate", {
            "expression": f'''
                (() => {{
                    const el = document.querySelector("{selector}");
                    if (!el) return "Element not found: {selector}";
                    el.focus();
                    el.value = {escaped_text};
                    el.dispatchEvent(new Event("input", {{ bubbles: true }}));
                    el.dispatchEvent(new Event("change", {{ bubbles: true }}));
                    return "typed";
                }})()
            ''',
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        val = result.get("result", {}).get("value", "")
        print(json.dumps({"result": val}))
    await bidi_session(run)


async def cmd_title(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": "document.title",
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        print(result.get("result", {}).get("value", ""))
    await bidi_session(run)


async def cmd_url(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": "window.location.href",
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        print(result.get("result", {}).get("value", ""))
    await bidi_session(run)


async def cmd_reload(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        await send("browsingContext.reload", {"context": ctx, "wait": "complete"})
        print(json.dumps({"result": "reloaded"}))
    await bidi_session(run)


async def cmd_back(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        await send("browsingContext.traverseHistory", {"context": ctx, "delta": -1})
        print(json.dumps({"result": "navigated back"}))
    await bidi_session(run)


async def cmd_forward(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        await send("browsingContext.traverseHistory", {"context": ctx, "delta": 1})
        print(json.dumps({"result": "navigated forward"}))
    await bidi_session(run)


async def cmd_new_tab(args):
    url = args[0] if args else "about:blank"

    async def run(send):
        result = await send("browsingContext.create", {"type": "tab"})
        ctx = result["context"]
        if url != "about:blank":
            await send("browsingContext.navigate", {
                "context": ctx, "url": url, "wait": "complete",
            })
        print(json.dumps({"context": ctx, "url": url}))
    await bidi_session(run)


async def cmd_close_tab(args):
    if not args:
        print(json.dumps({"error": "Usage: close_tab <context_id>"}))
        sys.exit(1)
    ctx_id = args[0]

    async def run(send):
        await send("browsingContext.close", {"context": ctx_id})
        print(json.dumps({"result": "closed", "context": ctx_id}))
    await bidi_session(run)


async def cmd_cookies(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": "document.cookie",
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        print(result.get("result", {}).get("value", ""))
    await bidi_session(run)


async def cmd_console_log(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": '''
                (() => {
                    if (!window.__bidiLogs) {
                        window.__bidiLogs = [];
                        const orig = console.log;
                        console.log = (...args) => {
                            window.__bidiLogs.push(args.map(a =>
                                typeof a === "object" ? JSON.stringify(a) : String(a)
                            ).join(" "));
                            if (window.__bidiLogs.length > 100) window.__bidiLogs.shift();
                            orig.apply(console, args);
                        };
                        return "Logger installed. Call again to retrieve logs.";
                    }
                    const logs = [...window.__bidiLogs];
                    window.__bidiLogs = [];
                    return logs.join("\\n");
                })()
            ''',
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        print(result.get("result", {}).get("value", ""))
    await bidi_session(run)


async def cmd_network(args):
    ctx_id = args[0] if args else None

    async def run(send):
        ctx = await get_default_context(send, ctx_id)
        result = await send("script.evaluate", {
            "expression": '''
                JSON.stringify(
                    performance.getEntriesByType("resource").slice(-20).map(e => ({
                        name: e.name,
                        type: e.initiatorType,
                        duration: Math.round(e.duration),
                        size: e.transferSize,
                    }))
                )
            ''',
            "target": {"context": ctx},
            "awaitPromise": False,
        })
        val = result.get("result", {}).get("value", "[]")
        try:
            print(json.dumps(json.loads(val), indent=2))
        except json.JSONDecodeError:
            print(val)
    await bidi_session(run)


COMMANDS = {
    "status": cmd_status,
    "tabs": cmd_tabs,
    "screenshot": cmd_screenshot,
    "eval": cmd_eval,
    "navigate": cmd_navigate,
    "html": cmd_html,
    "text": cmd_text,
    "click": cmd_click,
    "type": cmd_type,
    "title": cmd_title,
    "url": cmd_url,
    "reload": cmd_reload,
    "back": cmd_back,
    "forward": cmd_forward,
    "new_tab": cmd_new_tab,
    "close_tab": cmd_close_tab,
    "cookies": cmd_cookies,
    "console_log": cmd_console_log,
    "network": cmd_network,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    if cmd not in COMMANDS:
        print(f"Unknown command: {cmd}")
        print(f"Available commands: {', '.join(COMMANDS.keys())}")
        sys.exit(1)

    asyncio.run(COMMANDS[cmd](args))


if __name__ == "__main__":
    main()
