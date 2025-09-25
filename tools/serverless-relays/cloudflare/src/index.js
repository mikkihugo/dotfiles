/**
 * Cloudflare Worker - Secret Sync Relay
 * Handles encrypted sync data routing between devices
 * Uses Cloudflare KV for persistent storage
 */

const DEVICE_TTL = 600; // 10 minutes
const MESSAGE_TTL = 3600; // 1 hour
const MAX_MESSAGES_PER_DEVICE = 50;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return handleCORS();
    }

    try {
      // Route requests
      if (path === '/health') {
        return handleHealth(request);
      } else if (path.startsWith('/sync/')) {
        const roomId = path.split('/')[2];
        if (!roomId) {
          return jsonResponse({ error: 'Room ID required' }, 400);
        }
        return handleSync(request, env, roomId);
      } else {
        return jsonResponse({ error: 'Not found' }, 404);
      }
    } catch (error) {
      console.error('Worker error:', error);
      return jsonResponse({ error: 'Internal server error' }, 500);
    }
  }
};

async function handleHealth(request) {
  if (request.method !== 'GET') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  return jsonResponse({
    status: 'healthy',
    service: 'secret-sync-relay',
    timestamp: new Date().toISOString(),
    provider: 'cloudflare-workers',
    region: 'global-edge'
  });
}

async function handleSync(request, env, roomId) {
  const url = new URL(request.url);

  switch (request.method) {
    case 'POST':
      return handleSyncPost(request, env, roomId);
    case 'GET':
      return handleSyncGet(request, env, roomId, url.searchParams);
    default:
      return jsonResponse({ error: 'Method not allowed' }, 405);
  }
}

async function handleSyncPost(request, env, roomId) {
  const data = await request.json();
  const {
    from_device,
    encrypted_payload,
    to_devices,
    device_name,
    timestamp
  } = data;

  if (!from_device || !encrypted_payload) {
    return jsonResponse({
      error: 'from_device and encrypted_payload required'
    }, 400);
  }

  // Update sender's last seen
  await env.SYNC_KV.put(
    `device:${roomId}:${from_device}`,
    JSON.stringify({
      device_name: device_name || 'unknown',
      last_seen: new Date().toISOString(),
    }),
    { expirationTtl: DEVICE_TTL }
  );

  const syncMessage = {
    from_device,
    encrypted_payload,
    timestamp: timestamp || new Date().toISOString(),
    message_id: `${from_device}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  };

  // Get target devices
  let targetDevices = to_devices;
  if (!targetDevices || targetDevices.length === 0) {
    // Broadcast to all devices in room except sender
    const deviceList = await env.SYNC_KV.list({ prefix: `device:${roomId}:` });
    targetDevices = deviceList.keys
      .map(key => key.name.split(':')[2])
      .filter(deviceId => deviceId !== from_device);
  }

  let deliveredTo = [];

  // Store message for each target device
  for (const targetDevice of targetDevices) {
    const messageKey = `messages:${roomId}:${targetDevice}`;

    try {
      // Get existing messages
      const existingData = await env.SYNC_KV.get(messageKey);
      const existingMessages = existingData ? JSON.parse(existingData) : [];

      // Add new message
      const messages = [...existingMessages, syncMessage];

      // Keep only recent messages
      const trimmedMessages = messages.slice(-MAX_MESSAGES_PER_DEVICE);

      // Store with TTL
      await env.SYNC_KV.put(
        messageKey,
        JSON.stringify(trimmedMessages),
        { expirationTtl: MESSAGE_TTL }
      );

      deliveredTo.push(targetDevice);
    } catch (error) {
      console.error(`Failed to store message for ${targetDevice}:`, error);
    }
  }

  return jsonResponse({
    success: true,
    message_id: syncMessage.message_id,
    delivered_to: deliveredTo,
    room_id: roomId
  });
}

async function handleSyncGet(request, env, roomId, searchParams) {
  const deviceId = searchParams.get('device_id');

  if (!deviceId) {
    return jsonResponse({ error: 'device_id query parameter required' }, 400);
  }

  try {
    // Get pending messages
    const messageKey = `messages:${roomId}:${deviceId}`;
    const messageData = await env.SYNC_KV.get(messageKey);
    const messages = messageData ? JSON.parse(messageData) : [];

    // Clear messages after retrieval (mark as delivered)
    if (messages.length > 0) {
      await env.SYNC_KV.delete(messageKey);
    }

    // Update device last seen
    await env.SYNC_KV.put(
      `device:${roomId}:${deviceId}`,
      JSON.stringify({
        last_seen: new Date().toISOString(),
        retrieved_messages: messages.length
      }),
      { expirationTtl: DEVICE_TTL }
    );

    return jsonResponse({
      messages,
      count: messages.length,
      room_id: roomId
    });
  } catch (error) {
    console.error('Get messages error:', error);
    return jsonResponse({ error: 'Failed to retrieve messages' }, 500);
  }
}

function handleCORS() {
  return new Response(null, {
    status: 200,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400',
    }
  });
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    }
  });
}