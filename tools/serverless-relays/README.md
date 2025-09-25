# 🌐 Serverless Secret Sync Relays

Free serverless relay implementations for secret synchronization across machines. Choose your preferred provider based on your needs and existing accounts.

## 🎯 Quick Comparison

| Provider | Free Tier | Setup Complexity | Global Edge | Vendor Lock-in |
|----------|-----------|------------------|-------------|----------------|
| **Vercel** | 100GB bandwidth, serverless functions | Easy | ✅ Global | Low |
| **Netlify** | 125k invocations/month, 100h runtime | Easy | ✅ Global | Low |
| **Cloudflare** | 100k requests/day, 1GB KV storage | Medium | ✅ Global Edge | Medium |

## 🚀 Deployment Options

### Option 1: Vercel (Recommended for beginners)

```bash
cd vercel/
npm install
./deploy.sh
```

**Features:**
- ✅ Built-in KV storage
- ✅ Automatic HTTPS
- ✅ Easy deployment
- ✅ Great free tier

### Option 2: Netlify Functions

```bash
cd netlify/
npm install
./deploy.sh
```

**Features:**
- ✅ In-memory storage (simple)
- ✅ Great CI/CD integration
- ✅ Generous free tier
- ⚠️ Data doesn't persist across cold starts

### Option 3: Cloudflare Workers

```bash
cd cloudflare/
npm install
npm run kv:namespace:create
npm run kv:namespace:create:preview
# Update wrangler.toml with namespace IDs
./deploy.sh
```

**Features:**
- ✅ Global edge network
- ✅ Excellent performance
- ✅ Persistent KV storage
- ⚠️ More complex setup

## 🔧 Setup Instructions

### 1. Choose Your Provider

Pick one based on your preference:
- **Vercel**: Best overall experience
- **Netlify**: Great for teams already using Netlify
- **Cloudflare**: Best performance, most complex setup

### 2. Deploy Your Relay

Follow the deployment instructions for your chosen provider above.

### 3. Test Your Relay

```bash
# Replace with your deployed URL
RELAY_URL="https://your-app.vercel.app"

# Test health endpoint
curl "$RELAY_URL/health"

# Test sync (send message)
curl -X POST "$RELAY_URL/sync/test-room" \\
  -H "Content-Type: application/json" \\
  -d '{
    "from_device": "laptop",
    "encrypted_payload": "test-encrypted-data",
    "device_name": "My Laptop"
  }'

# Test sync (receive messages)
curl "$RELAY_URL/sync/test-room?device_id=phone"
```

### 4. Configure in Secret TUI

Update your secret TUI configuration:

```rust
// In your sync configuration
SyncMethod::Relay {
    server_url: "https://your-app.vercel.app".to_string(),
    room_id: "your-shared-secret-room-id".to_string(),
}
```

## 🔐 Security Features

All implementations provide:
- ✅ **Zero-knowledge design**: Server never sees decrypted data
- ✅ **End-to-end encryption**: ChaCha20-Poly1305 on top of SOPS
- ✅ **Automatic cleanup**: Messages expire after 1 hour
- ✅ **Room isolation**: Devices only see messages in their room
- ✅ **CORS enabled**: Works from any origin

## 💰 Cost Comparison

### Free Tier Limits

**Vercel:**
- 100GB bandwidth/month
- Serverless function invocations included
- KV storage: 30GB read, 1GB write

**Netlify:**
- 125,000 function invocations/month
- 100 hours runtime/month
- Bandwidth: 100GB/month

**Cloudflare Workers:**
- 100,000 requests/day (3M/month)
- 1GB KV storage
- Global edge network

### Estimated Usage for Secret Sync

Assuming 4 devices syncing 10 secrets/day:
- ~120 API calls/month
- ~50KB data transfer/month
- Well within all free tiers! 🎉

## 🛠️ Development

### Local Testing

Each provider includes local development:

```bash
# Vercel
cd vercel && vercel dev

# Netlify
cd netlify && netlify dev

# Cloudflare
cd cloudflare && wrangler dev
```

### Custom Modifications

All implementations follow the same API:
- `GET /health` - Health check
- `POST /sync/{roomId}` - Send encrypted message
- `GET /sync/{roomId}?device_id=X` - Receive messages

Modify the storage backend or add features as needed.

## 🐛 Troubleshooting

### Common Issues

**"Room ID required"**
- Make sure your URL includes the room ID: `/sync/your-room-id`

**"device_id query parameter required"**
- GET requests need: `?device_id=your-device-id`

**CORS errors**
- All implementations include CORS headers
- Check browser dev tools for specific errors

**Messages not persisting**
- Netlify: Uses in-memory storage (resets on cold start)
- Vercel/Cloudflare: Use persistent KV storage

### Performance Tips

1. **Use short room IDs**: Better URL readability
2. **Implement client-side caching**: Reduce API calls
3. **Batch messages**: Send multiple secrets together
4. **Use appropriate TTL**: Balance availability vs security

## 🚀 Production Recommendations

1. **Custom Domain**: Set up your own domain for the relay
2. **Rate Limiting**: Add rate limiting for production use
3. **Monitoring**: Set up alerts for function errors
4. **Backup Strategy**: Consider multiple providers for redundancy
5. **Authentication**: Add device authentication for enhanced security

## 📚 Related Files

- `../secret-tui-rust/src/sync.rs` - Rust client implementation
- `../secret-relay-server.py` - Self-hosted Python server
- `../webhook-sync-example.js` - Express.js webhook server

Choose the deployment method that best fits your infrastructure and team preferences!