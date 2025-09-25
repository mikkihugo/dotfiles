/**
 * Netlify Function - Secret Sync Relay
 * Handles encrypted sync data routing between devices
 * Uses Netlify's built-in key-value storage (Redis alternative)
 */

// Simple in-memory storage for free tier (use external DB for production)
const storage = new Map();
const DEVICE_TTL = 600000; // 10 minutes
const MESSAGE_TTL = 3600000; // 1 hour
const MAX_MESSAGES_PER_DEVICE = 50;

// Cleanup function
function cleanupOldData() {
  const now = Date.now();

  for (const [key, value] of storage.entries()) {
    if (key.startsWith('device:') && value.expires && now > value.expires) {
      storage.delete(key);
    }
    if (key.startsWith('messages:') && value.expires && now > value.expires) {
      storage.delete(key);
    }
  }
}

exports.handler = async (event, context) => {
  // Periodic cleanup
  cleanupOldData();

  const { path, httpMethod, queryStringParameters, body } = event;
  const pathMatch = path.match(/\/sync\/([^\/]+)/);

  if (!pathMatch) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'Room ID required in path: /sync/{roomId}' })
    };
  }

  const roomId = pathMatch[1];

  try {
    switch (httpMethod) {
      case 'POST':
        return await handleSync(roomId, body);
      case 'GET':
        return await getPendingMessages(roomId, queryStringParameters);
      default:
        return {
          statusCode: 405,
          body: JSON.stringify({ error: 'Method not allowed' })
        };
    }
  } catch (error) {
    console.error('Sync error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};

async function handleSync(roomId, requestBody) {
  const data = JSON.parse(requestBody || '{}');
  const {
    from_device,
    encrypted_payload,
    to_devices,
    device_name,
    timestamp
  } = data;

  if (!from_device || !encrypted_payload) {
    return {
      statusCode: 400,
      body: JSON.stringify({
        error: 'from_device and encrypted_payload required'
      })
    };
  }

  const now = Date.now();

  // Update sender's last seen
  storage.set(`device:${roomId}:${from_device}`, {
    device_name: device_name || 'unknown',
    last_seen: new Date().toISOString(),
    expires: now + DEVICE_TTL
  });

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
    targetDevices = [];
    for (const [key] of storage.entries()) {
      if (key.startsWith(`device:${roomId}:`)) {
        const deviceId = key.split(':')[2];
        if (deviceId !== from_device) {
          targetDevices.push(deviceId);
        }
      }
    }
  }

  let deliveredTo = [];

  // Store message for each target device
  for (const targetDevice of targetDevices) {
    const messageKey = `messages:${roomId}:${targetDevice}`;

    try {
      // Get existing messages
      const existingData = storage.get(messageKey) || { messages: [], expires: now + MESSAGE_TTL };
      const existingMessages = existingData.messages || [];

      // Add new message
      const messages = [...existingMessages, syncMessage];

      // Keep only recent messages
      const trimmedMessages = messages.slice(-MAX_MESSAGES_PER_DEVICE);

      // Store with TTL
      storage.set(messageKey, {
        messages: trimmedMessages,
        expires: now + MESSAGE_TTL
      });

      deliveredTo.push(targetDevice);
    } catch (error) {
      console.error(`Failed to store message for ${targetDevice}:`, error);
    }
  }

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify({
      success: true,
      message_id: syncMessage.message_id,
      delivered_to: deliveredTo,
      room_id: roomId
    })
  };
}

async function getPendingMessages(roomId, queryParams) {
  const deviceId = queryParams?.device_id;

  if (!deviceId) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'device_id query parameter required' })
    };
  }

  try {
    // Get pending messages
    const messageKey = `messages:${roomId}:${deviceId}`;
    const messageData = storage.get(messageKey);
    const messages = messageData?.messages || [];

    // Clear messages after retrieval (mark as delivered)
    if (messages.length > 0) {
      storage.delete(messageKey);
    }

    // Update device last seen
    const now = Date.now();
    storage.set(`device:${roomId}:${deviceId}`, {
      last_seen: new Date().toISOString(),
      retrieved_messages: messages.length,
      expires: now + DEVICE_TTL
    });

    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        messages,
        count: messages.length,
        room_id: roomId
      })
    };
  } catch (error) {
    console.error('Get messages error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Failed to retrieve messages' })
    };
  }
}