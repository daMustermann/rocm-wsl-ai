#!/usr/bin/env python3
import http.server
import socketserver
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8188

HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Waking up AI Engine...</title>
    <style>
        body { background: #1a1b26; color: #a9b1d6; font-family: system-ui, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .container { text-align: center; }
        .spinner { width: 50px; height: 50px; border: 5px solid #24283b; border-top: 5px solid #7aa2f7; border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 20px; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        h1 { color: #7aa2f7; margin-bottom: 5px; }
        p { color: #9ece6a; }
    </style>
    <script>
        // Reload heavily after 8 seconds (time enough for PyTorch to start and webserver to bind)
        setTimeout(() => { window.location.reload(); }, 8000);
    </script>
</head>
<body>
    <div class="container">
        <div class="spinner"></div>
        <h1>Waking up AI Engine...</h1>
        <p>Allocating VRAM and starting PyTorch. We'll refresh automatically in a few seconds!</p>
    </div>
</body>
</html>
"""

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(HTML.encode("utf-8"))
        print("\n[SMART SLEEP] Wake hit received! Exiting wake server and releasing port...", flush=True)
        # Violently kill this server so the bash loop can immediately reboot the real AI tool
        os._exit(0)

# Important to allow address reuse so it binds instantly after ComfyUI dies
socketserver.TCPServer.allow_reuse_address = True

try:
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"[SMART SLEEP] Wake server active on port {PORT}. Waiting for incoming connection...", flush=True)
        httpd.serve_forever()
except KeyboardInterrupt:
    print("[SMART SLEEP] Wake server manually aborted.")
    os._exit(1)
except Exception as e:
    print(f"[SMART SLEEP] Wake server error: {e}")
    os._exit(1)
