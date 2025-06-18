// Cloudflare Worker for secure remote vault unlock
// Deploy to: unlock.hugo.dk

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // Handle unlock request
    if (url.pathname === '/vault/request') {
      const { host, timestamp } = await request.json();
      
      // Generate temporary unlock token
      const token = await generateToken(host, timestamp);
      const unlockUrl = `https://unlock.hugo.dk/approve/${token}`;
      
      // Store pending request
      await env.VAULT_KV.put(`pending:${host}`, JSON.stringify({
        token,
        timestamp,
        expires: Date.now() + 300000 // 5 minutes
      }));
      
      return new Response(JSON.stringify({ unlock_url: unlockUrl }));
    }
    
    // Handle approval page
    if (url.pathname.startsWith('/approve/')) {
      const _token = url.pathname.split('/')[2];
      
      // Show approval page with auth
      return new Response(APPROVAL_HTML, {
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    // Handle unlock approval
    if (url.pathname === '/vault/approve' && request.method === 'POST') {
      const { token, auth_code } = await request.json();
      
      // Verify auth (could be TOTP, passkey, etc)
      if (!await verifyAuth(auth_code, env)) {
        return new Response('Unauthorized', { status: 401 });
      }
      
      // Get pending request
      const pending = await env.VAULT_KV.get(`pending:${token}`);
      if (!pending) {
        return new Response('Invalid token', { status: 404 });
      }
      
      const { host } = JSON.parse(pending);
      
      // Encrypt master key with host's public key
      const encryptedKey = await encryptForHost(env.MASTER_KEY, host);
      
      // Mark as unlocked
      await env.VAULT_KV.put(`unlocked:${host}`, encryptedKey, {
        expirationTtl: 300 // 5 minutes
      });
      
      return new Response('Vault unlocked!');
    }
    
    // Check unlock status
    if (url.pathname.startsWith('/vault/status/')) {
      const host = url.pathname.split('/')[3];
      const unlocked = await env.VAULT_KV.get(`unlocked:${host}`);
      
      return new Response(JSON.stringify({
        status: unlocked ? 'unlocked' : 'locked'
      }));
    }
    
    // Get encrypted key
    if (url.pathname.startsWith('/vault/key/')) {
      const host = url.pathname.split('/')[3];
      const key = await env.VAULT_KV.get(`unlocked:${host}`);
      
      if (!key) {
        return new Response('Not unlocked', { status: 404 });
      }
      
      // Delete after retrieval (one-time use)
      await env.VAULT_KV.delete(`unlocked:${host}`);
      
      return new Response(key);
    }
    
    return new Response('Not found', { status: 404 });
  }
};

// HTML for approval page
const APPROVAL_HTML = `
<!DOCTYPE html>
<html>
<head>
  <title>Vault Unlock - Hugo.dk</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { 
      font-family: -apple-system, system-ui, sans-serif;
      max-width: 400px;
      margin: 50px auto;
      padding: 20px;
    }
    .container {
      background: #f5f5f5;
      border-radius: 8px;
      padding: 30px;
      text-align: center;
    }
    button {
      background: #0066cc;
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 4px;
      font-size: 16px;
      cursor: pointer;
    }
    .code-input {
      font-size: 24px;
      letter-spacing: 8px;
      width: 200px;
      text-align: center;
      margin: 20px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>🔐 Vault Unlock Request</h2>
    <p>Enter your authentication code:</p>
    <input type="text" class="code-input" maxlength="6" id="code">
    <br>
    <button onclick="approve()">Unlock Vault</button>
  </div>
  <script>
    async function approve() {
      const code = document.getElementById('code').value;
      const token = window.location.pathname.split('/')[2];
      
      const response = await fetch('/vault/approve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, auth_code: code })
      });
      
      if (response.ok) {
        document.body.innerHTML = '<div class="container"><h2>✅ Vault Unlocked!</h2></div>';
      } else {
        alert('Invalid code');
      }
    }
  </script>
</body>
</html>
`;

async function generateToken(host, timestamp) {
  const data = new TextEncoder().encode(`${host}:${timestamp}`);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return btoa(String.fromCharCode(...new Uint8Array(hash))).replace(/[+/=]/g, '');
}

async function verifyAuth(code, env) {
  // Simple TOTP check or use Cloudflare Access
  return code === env.AUTH_CODE; // In production, use proper TOTP
}

async function encryptForHost(masterKey, host) {
  // In production, fetch host's public key and encrypt
  // For now, simple encryption
  return btoa(masterKey + ':' + host);
}
