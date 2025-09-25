/**
 * Vercel Serverless Function - Secret Sync Relay
 * Handles encrypted sync data routing between devices
 */

import { kv } from '@vercel/kv';

const DEVICE_TTL = 600; // 10 minutes
const MESSAGE_TTL = 3600; // 1 hour
const MAX_MESSAGES_PER_DEVICE = 50;

export default async function handler(req, res) {
  const { roomId } = req.query;

  if (!roomId) {
    return res.status(400).json({ error: 'Room ID required' });
  }

  try {
    switch (req.method) {
      case 'POST':
        return await handleSync(req, res, roomId);
      case 'GET':
        return await getPendingMessages(req, res, roomId);
      default:
        return res.status(405).json({ error: 'Method not allowed' });
    }
  } catch (error) {
    console.error('Sync error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function handleSync(req, res, roomId) {
  const {
    from_device,
    encrypted_payload,
    to_devices,
    device_name,
    timestamp
  } = req.body;

  if (!from_device || !encrypted_payload) {
    return res.status(400).json({
      error: 'from_device and encrypted_payload required'
    });
  }

  // Update sender's last seen
  await kv.setex(`device:${roomId}:${from_device}`, DEVICE_TTL, {
    device_name: device_name || 'unknown',
    last_seen: new Date().toISOString(),
    ip: req.headers['x-forwarded-for'] || 'unknown'
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
    const deviceKeys = await kv.keys(`device:${roomId}:*`);
    targetDevices = deviceKeys
      .map(key => key.split(':')[2])
      .filter(deviceId => deviceId !== from_device);
  }

  let deliveredTo = [];

  // Store message for each target device
  for (const targetDevice of targetDevices) {
    const messageKey = `messages:${roomId}:${targetDevice}`;

    try {
      // Get existing messages
      const existingMessages = await kv.get(messageKey) || [];

      // Add new message
      const messages = [...existingMessages, syncMessage];

      // Keep only recent messages
      const trimmedMessages = messages.slice(-MAX_MESSAGES_PER_DEVICE);

      // Store with TTL
      await kv.setex(messageKey, MESSAGE_TTL, trimmedMessages);

      deliveredTo.push(targetDevice);
    } catch (error) {
      console.error(`Failed to store message for ${targetDevice}:`, error);
    }
  }

  return res.status(200).json({
    success: true,
    message_id: syncMessage.message_id,
    delivered_to: deliveredTo,
    room_id: roomId
  });
}

async function getPendingMessages(req, res, roomId) {
  const deviceId = req.query.device_id;

  if (!deviceId) {
    return res.status(400).json({ error: 'device_id query parameter required' });
  }

  try {
    // Get pending messages
    const messageKey = `messages:${roomId}:${deviceId}`;
    const messages = await kv.get(messageKey) || [];

    // Clear messages after retrieval (mark as delivered)
    if (messages.length > 0) {
      await kv.del(messageKey);
    }

    // Update device last seen
    await kv.setex(`device:${roomId}:${deviceId}`, DEVICE_TTL, {
      last_seen: new Date().toISOString(),
      retrieved_messages: messages.length
    });

    return res.status(200).json({
      messages,
      count: messages.length,
      room_id: roomId
    });
  } catch (error) {
    console.error('Get messages error:', error);
    return res.status(500).json({ error: 'Failed to retrieve messages' });
  }
}