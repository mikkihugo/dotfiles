#!/usr/bin/env node

/**
 * Example webhook receiver for secret sync
 * Deploy this on any cloud service (Vercel, Heroku, DigitalOcean, etc.)
 */

const express = require('express');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3000;

// In-memory storage (use database in production)
const syncMessages = new Map(); // device_id -> messages[]
const deviceTokens = new Map();  // device_id -> auth_token

app.use(express.json({ limit: '10mb' }));

// Middleware for authentication
const authenticate = (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or invalid authorization header' });
    }

    const token = authHeader.substring(7);
    const deviceId = req.headers['x-device-id'];

    if (!deviceId) {
        return res.status(400).json({ error: 'Missing device ID header' });
    }

    // Simple token validation (use proper JWT in production)
    if (!deviceTokens.has(deviceId) || deviceTokens.get(deviceId) !== token) {
        return res.status(403).json({ error: 'Invalid device token' });
    }

    req.deviceId = deviceId;
    next();
};

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        active_devices: deviceTokens.size,
        pending_messages: Array.from(syncMessages.values()).reduce((sum, msgs) => sum + msgs.length, 0)
    });
});

// Register device
app.post('/register', (req, res) => {
    const { device_id, device_name, auth_token } = req.body;

    if (!device_id || !auth_token) {
        return res.status(400).json({ error: 'Missing device_id or auth_token' });
    }

    deviceTokens.set(device_id, auth_token);

    if (!syncMessages.has(device_id)) {
        syncMessages.set(device_id, []);
    }

    console.log(`📱 Device registered: ${device_name} (${device_id})`);

    res.json({
        success: true,
        message: 'Device registered successfully',
        peer_count: deviceTokens.size - 1
    });
});

// Receive sync data
app.post('/sync', authenticate, (req, res) => {
    const { encrypted_payload, target_devices, timestamp } = req.body;
    const fromDevice = req.deviceId;

    if (!encrypted_payload) {
        return res.status(400).json({ error: 'Missing encrypted_payload' });
    }

    const syncMessage = {
        from_device: fromDevice,
        encrypted_payload,
        timestamp: timestamp || new Date().toISOString(),
        message_id: `${fromDevice}_${Date.now()}`
    };

    let deliveredTo = [];

    // If target_devices specified, send only to those
    const targets = target_devices || Array.from(deviceTokens.keys()).filter(id => id !== fromDevice);

    targets.forEach(targetDevice => {
        if (deviceTokens.has(targetDevice)) {
            if (!syncMessages.has(targetDevice)) {
                syncMessages.set(targetDevice, []);
            }

            const messages = syncMessages.get(targetDevice);
            messages.push(syncMessage);

            // Keep only last 100 messages per device
            if (messages.length > 100) {
                messages.splice(0, messages.length - 100);
            }

            deliveredTo.push(targetDevice);
        }
    });

    console.log(`🔄 Sync message from ${fromDevice} delivered to ${deliveredTo.length} devices`);

    res.json({
        success: true,
        delivered_to: deliveredTo,
        message_id: syncMessage.message_id
    });
});

// Retrieve pending sync messages
app.get('/sync', authenticate, (req, res) => {
    const deviceId = req.deviceId;
    const messages = syncMessages.get(deviceId) || [];

    // Mark as delivered by clearing messages
    syncMessages.set(deviceId, []);

    res.json({
        messages,
        count: messages.length
    });
});

// Get list of registered devices (for discovery)
app.get('/devices', authenticate, (req, res) => {
    const deviceId = req.deviceId;
    const peers = Array.from(deviceTokens.keys()).filter(id => id !== deviceId);

    res.json({
        peers: peers.map(peer => ({
            device_id: peer,
            last_seen: new Date().toISOString() // Simplified
        }))
    });
});

// Cleanup old messages periodically
setInterval(() => {
    const now = Date.now();
    const maxAge = 24 * 60 * 60 * 1000; // 24 hours

    for (const [deviceId, messages] of syncMessages.entries()) {
        const filtered = messages.filter(msg => {
            const msgTime = new Date(msg.timestamp).getTime();
            return now - msgTime < maxAge;
        });

        if (filtered.length !== messages.length) {
            syncMessages.set(deviceId, filtered);
            console.log(`🧹 Cleaned up ${messages.length - filtered.length} old messages for ${deviceId}`);
        }
    }
}, 60 * 60 * 1000); // Run every hour

// Error handling
app.use((err, req, res, next) => {
    console.error('Error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
    console.log(`🌐 Webhook Sync Server running on port ${PORT}`);
    console.log(`📡 Endpoints:`);
    console.log(`   POST /register  - Register device`);
    console.log(`   POST /sync      - Send sync data`);
    console.log(`   GET  /sync      - Retrieve sync data`);
    console.log(`   GET  /devices   - List peers`);
    console.log(`   GET  /health    - Health check`);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n👋 Shutting down webhook server...');
    process.exit(0);
});