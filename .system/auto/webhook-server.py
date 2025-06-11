#!/usr/bin/env python3
"""
Simple webhook server for dotfiles auto-sync
Listens for GitHub webhook pushes and triggers sync script
"""

import hmac
import hashlib
import subprocess
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

# Get webhook secret from environment
WEBHOOK_SECRET = os.environ.get('GITHUB_WEBHOOK_SECRET', '')
SYNC_SCRIPT = os.path.expanduser('~/.dotfiles/.scripts/webhook-sync.sh')

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/webhook':
            self.send_response(404)
            self.end_headers()
            return
        
        # Get content length
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        
        # Verify signature if secret is set
        if WEBHOOK_SECRET:
            signature = self.headers.get('X-Hub-Signature-256', '')
            expected_signature = 'sha256=' + hmac.new(
                WEBHOOK_SECRET.encode(),
                post_data,
                hashlib.sha256
            ).hexdigest()
            
            if not hmac.compare_digest(signature, expected_signature):
                self.send_response(401)
                self.end_headers()
                return
        
        try:
            # Parse JSON payload
            payload = json.loads(post_data.decode())
            
            # Check if this is a push to main branch
            if payload.get('ref') == 'refs/heads/main':
                print(f"Received push to main branch, triggering sync...")
                
                # Run sync script in background
                subprocess.Popen([SYNC_SCRIPT], 
                               stdout=subprocess.DEVNULL, 
                               stderr=subprocess.DEVNULL)
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Sync triggered successfully')
                
                print(f"Sync triggered for commit: {payload.get('head_commit', {}).get('id', 'unknown')}")
            else:
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Ignored: not main branch')
                
        except Exception as e:
            print(f"Error processing webhook: {e}")
            self.send_response(500)
            self.end_headers()
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Webhook server is running')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    port = int(os.environ.get('WEBHOOK_PORT', 8080))
    server = HTTPServer(('0.0.0.0', port), WebhookHandler)
    print(f"Webhook server starting on port {port}...")
    print(f"Endpoint: http://your-server:{port}/webhook")
    print(f"Health check: http://your-server:{port}/health")
    server.serve_forever()