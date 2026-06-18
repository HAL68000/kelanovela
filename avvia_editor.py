#!/usr/bin/env python3
"""
Godot Map Editor — Server locale con proxy LM Studio
Elimina il problema CORS aprendo il file via http://localhost:8765
invece di file://

Uso:
    python3 avvia_editor.py
    oppure
    python3 avvia_editor.py --port 8765 --lmstudio http://localhost:1234

Il browser si apre automaticamente.
"""

import argparse
import http.server
import json
import os
import sys
import threading
import urllib.request
import urllib.error
import webbrowser
from pathlib import Path

# ── Argomenti ────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="Godot Map Editor proxy server")
parser.add_argument("--port",     type=int, default=8765,                  help="Porta locale (default 8765)")
parser.add_argument("--lmstudio", type=str, default="http://localhost:1234", help="URL LM Studio")
args = parser.parse_args()

LM_BASE = args.lmstudio.rstrip("/")
PORT    = args.port
DIR     = Path(__file__).parent          # stessa cartella dello script

CORS_HEADERS = {
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
}

# ── Handler ──────────────────────────────────────────────────────────────────
class Handler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *a):
        # stampa solo errori, non ogni richiesta
        if a and str(a[1]) not in ("200", "204"):
            print(f"  {fmt % a}")

    # ---------- OPTIONS (preflight) -----------------------------------------
    def do_OPTIONS(self):
        self.send_response(204)
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)
        self.end_headers()

    # ---------- GET ----------------------------------------------------------
    def do_GET(self):
        path = self.path.split("?")[0]

        # Proxy → LM Studio
        if path.startswith("/lm/"):
            lm_path = path[3:]          # /lm/v1/models → /v1/models
            self._proxy_get(lm_path)
            return

        # Serve file statici dalla stessa cartella
        if path == "/" or path == "":
            path = "/godot_map_editor.html"

        file_path = DIR / path.lstrip("/")
        if file_path.exists() and file_path.is_file():
            self._serve_file(file_path)
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")

    # ---------- POST ---------------------------------------------------------
    def do_POST(self):
        path = self.path
        if path.startswith("/lm/"):
            lm_path = path[3:]
            length  = int(self.headers.get("Content-Length", 0))
            body    = self.rfile.read(length)
            self._proxy_post(lm_path, body)
        else:
            self.send_response(404)
            self.end_headers()

    # ---------- helpers ------------------------------------------------------
    def _serve_file(self, path: Path):
        ext = path.suffix.lower()
        mime = {
            ".html": "text/html; charset=utf-8",
            ".js":   "application/javascript",
            ".css":  "text/css",
            ".png":  "image/png",
            ".jpg":  "image/jpeg",
            ".svg":  "image/svg+xml",
        }.get(ext, "application/octet-stream")

        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", len(data))
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _proxy_get(self, lm_path: str):
        url = LM_BASE + lm_path
        try:
            req  = urllib.request.Request(url)
            resp = urllib.request.urlopen(req, timeout=10)
            body = resp.read()
            self.send_response(resp.status)
            self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
            for k, v in CORS_HEADERS.items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            self._error(str(e))

    def _proxy_post(self, lm_path: str, body: bytes):
        url = LM_BASE + lm_path
        try:
            req  = urllib.request.Request(url, data=body,
                       headers={"Content-Type": "application/json"})
            resp = urllib.request.urlopen(req, timeout=120)
            body_out = resp.read()
            self.send_response(resp.status)
            self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
            for k, v in CORS_HEADERS.items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body_out)
        except urllib.error.HTTPError as e:
            body_err = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            for k, v in CORS_HEADERS.items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body_err)
        except Exception as e:
            self._error(str(e))

    def _error(self, msg: str):
        data = json.dumps({"error": msg}).encode()
        self.send_response(502)
        self.send_header("Content-Type", "application/json")
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)

    url = f"http://localhost:{PORT}/godot_map_editor.html"
    print("=" * 56)
    print("  Godot Map Editor — server locale avviato")
    print("=" * 56)
    print(f"  Editor  →  {url}")
    print(f"  Proxy   →  /lm/...  →  {LM_BASE}")
    print("  Premi Ctrl+C per fermare")
    print("=" * 56)

    # apri browser dopo 0.5s (server già in ascolto)
    threading.Timer(0.5, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Server fermato.")

if __name__ == "__main__":
    main()
