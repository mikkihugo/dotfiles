# 🚀 Serverless Secret Sync Setup Guide

This guide shows you how to set up free serverless relays for synchronizing secrets between your devices using the secret-tui Rust application.

## 🎯 Quick Start

1. **Choose a serverless provider** (Vercel recommended for beginners)
2. **Deploy the relay** using the provided scripts
3. **Configure your secret-tui** with the relay URL
4. **Start syncing secrets** securely between devices!

## 📋 Prerequisites

- Node.js 18+ installed
- Account with your chosen serverless provider
- The secret-tui Rust application built and working

## 🔧 Option 1: Vercel (Recommended)

### Deploy to Vercel

```bash
cd ../serverless-relays/vercel/
npm install
npm install -g vercel    # If not already installed
vercel login            # Login to your Vercel account
./deploy.sh
```

### Configure KV Storage

1. Go to your Vercel dashboard
2. Navigate to your deployed project
3. Go to "Storage" → "Create Database" → "KV"
4. Note the `KV_REST_API_URL` and `KV_REST_API_TOKEN`
5. Add these as environment variables in your Vercel project

### Configure secret-tui

```rust
// Add to your sync configuration
sync.add_vercel_relay(
    "https://your-app.vercel.app".to_string(),
    "your-shared-room-id".to_string(),
)?;
```

## 🔧 Option 2: Netlify Functions

### Deploy to Netlify

```bash
cd ../serverless-relays/netlify/
npm install
npm install -g netlify-cli    # If not already installed
netlify login                # Login to your Netlify account
./deploy.sh
```

### Configure secret-tui

```rust
// Add to your sync configuration
sync.add_netlify_relay(
    "https://your-app.netlify.app".to_string(),
    "your-shared-room-id".to_string(),
)?;
```

## 🔧 Option 3: Cloudflare Workers

### Deploy to Cloudflare

```bash
cd ../serverless-relays/cloudflare/
npm install
npm install -g wrangler    # If not already installed
wrangler login            # Login to your Cloudflare account

# Create KV namespaces
npm run kv:namespace:create
npm run kv:namespace:create:preview

# Update wrangler.toml with the namespace IDs from the output above

./deploy.sh
```

### Configure secret-tui

```rust
// Add to your sync configuration
sync.add_cloudflare_relay(
    "https://secret-sync.your-subdomain.workers.dev".to_string(),
    "your-shared-room-id".to_string(),
)?;
```

## 🔐 Security Configuration

### Room ID Best Practices

Your `room_id` acts as a shared secret between your devices. Choose something:
- **Unique**: Not guessable by others
- **Shared**: Same across all your devices
- **Memorable**: Easy to type on new devices

Examples:
- `family-secrets-2024-device-sync`
- `john-doe-personal-vault-sync`
- `company-team-dev-secrets-room`

### Key Management

Each device needs the same sync key. The secret-tui will:
1. Generate a unique sync key on first run
2. Save it in `.sync-config.json`
3. Share it via QR code for easy device pairing

## 📱 Device Pairing

### On your first device:
```bash
# Start the secret-tui
cargo run

# Navigate to: Sync Menu → Setup → Generate QR Code
# A QR code will be displayed with your sync configuration
```

### On additional devices:
```bash
# Start the secret-tui
cargo run

# Navigate to: Sync Menu → Setup → Scan QR Code
# Scan the QR code from your first device
```

## 🧪 Testing Your Setup

Use the provided test script:

```bash
cd ../
export VERCEL_URL="https://your-app.vercel.app"
export NETLIFY_URL="https://your-app.netlify.app"
export CLOUDFLARE_URL="https://secret-sync.your-subdomain.workers.dev"
./test-serverless-relay.sh
```

## 🎛️ Configuration Examples

### Minimal Configuration (Vercel only)
```json
{
  "device_name": "my-laptop",
  "sync_key": "generated-key-here",
  "auto_sync": false,
  "sync_methods": [
    {
      "ServerlessRelay": {
        "provider": "Vercel",
        "server_url": "https://your-app.vercel.app",
        "room_id": "my-secret-room"
      }
    }
  ]
}
```

### Multi-Provider Redundancy
```json
{
  "device_name": "my-laptop",
  "sync_key": "generated-key-here",
  "auto_sync": true,
  "sync_methods": [
    {
      "LocalNetwork": {
        "port": 8765,
        "discovery_port": 8766
      }
    },
    {
      "ServerlessRelay": {
        "provider": "Vercel",
        "server_url": "https://your-app.vercel.app",
        "room_id": "my-secret-room"
      }
    },
    {
      "ServerlessRelay": {
        "provider": "Netlify",
        "server_url": "https://your-app.netlify.app",
        "room_id": "my-secret-room"
      }
    }
  ]
}
```

## 💰 Cost Analysis

All providers offer generous free tiers perfect for personal secret sync:

### Vercel Free Tier
- ✅ 100GB bandwidth/month
- ✅ Unlimited function invocations
- ✅ 30GB KV read operations
- ✅ 1GB KV write operations

### Netlify Free Tier
- ✅ 125,000 function invocations/month
- ✅ 100 hours runtime/month
- ✅ 100GB bandwidth/month

### Cloudflare Workers Free Tier
- ✅ 100,000 requests/day (3M/month)
- ✅ 1GB KV storage
- ✅ Global edge network

### Typical Usage
For a family with 4 devices syncing 20 secrets daily:
- ~500 API calls/month
- ~200KB data transfer/month
- **Well within all free tiers!** 🎉

## 🐛 Troubleshooting

### Common Issues

**"Failed to connect to serverless relay"**
- Check your URL is correct and accessible
- Verify the relay is deployed and running
- Test with `curl https://your-app.vercel.app/health`

**"Room not found" errors**
- Ensure all devices use the exact same `room_id`
- Room IDs are case-sensitive

**"Sync key mismatch"**
- All devices must have the same sync key
- Re-pair devices using QR codes if needed

**CORS errors in testing**
- All implementations include proper CORS headers
- This shouldn't happen with the provided code

### Debug Mode

Enable debug logging:
```bash
RUST_LOG=debug cargo run
```

### Health Checks

Test your deployed endpoints:
```bash
# Health check
curl https://your-app.vercel.app/health

# Send test message
curl -X POST https://your-app.vercel.app/sync/test-room \
  -H "Content-Type: application/json" \
  -d '{"from_device":"test","encrypted_payload":"test-data"}'

# Retrieve messages
curl "https://your-app.vercel.app/sync/test-room?device_id=test2"
```

## 🎯 Next Steps

1. **Deploy your preferred serverless provider**
2. **Configure the secret-tui with your relay URL**
3. **Set up additional devices using QR code pairing**
4. **Start syncing your secrets securely across devices!**

## 🔒 Security Notes

- ✅ **Zero-knowledge design**: Serverless relay never sees decrypted secrets
- ✅ **End-to-end encryption**: ChaCha20-Poly1305 encryption happens client-side
- ✅ **Automatic expiry**: Messages expire after 1 hour
- ✅ **Room isolation**: Devices only access their own room's messages
- ✅ **Open source**: All code is auditable and transparent

Your secrets are encrypted before leaving your device and remain encrypted until they reach your other devices. The serverless relay only handles encrypted blobs!