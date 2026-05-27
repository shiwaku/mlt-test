#!/usr/bin/env python3
"""Simple tile server for MLT testing with CORS support."""
import http.server
import os

PORT = 8765
BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs")

class TileHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE_DIR, **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".mlt"):
            return "application/x-protobuf"
        if path.endswith(".pbf"):
            return "application/x-protobuf"
        return super().guess_type(path)

    def log_message(self, format, *args):
        pass  # suppress access logs

if __name__ == "__main__":
    with http.server.HTTPServer(("", PORT), TileHandler) as httpd:
        print(f"Tile server running at http://localhost:{PORT}")
        print("Open index.html in a browser to view MLT tiles.")
        print("Press Ctrl+C to stop.")
        httpd.serve_forever()
