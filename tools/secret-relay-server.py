#!/usr/bin/env python3
"""
Simple relay server for secret sync over internet
Zero-knowledge design - server never sees decrypted data
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Set
import aiohttp
from aiohttp import web, WSMsgType
import argparse

# In-memory storage (use Redis/DB for production)
rooms: Dict[str, Dict] = {}  # room_id -> room_data
connections: Dict[str, web.WebSocketResponse] = {}  # device_id -> websocket

class SecretRelayServer:
    def __init__(self, host='0.0.0.0', port=8080, cleanup_interval=300):
        self.host = host
        self.port = port
        self.cleanup_interval = cleanup_interval
        self.app = web.Application()
        self.setup_routes()

    def setup_routes(self):
        """Setup HTTP and WebSocket routes"""
        self.app.router.add_get('/', self.health_check)
        self.app.router.add_get('/health', self.health_check)

        # Room management
        self.app.router.add_post('/room/{room_id}/join', self.join_room)
        self.app.router.add_get('/room/{room_id}/peers', self.get_peers)
        self.app.router.add_post('/room/{room_id}/sync', self.relay_sync)

        # WebSocket for real-time sync
        self.app.router.add_get('/room/{room_id}/ws', self.websocket_handler)

        # Admin endpoints
        self.app.router.add_get('/admin/rooms', self.list_rooms)
        self.app.router.add_get('/admin/stats', self.get_stats)

    async def health_check(self, request):
        """Health check endpoint"""
        return web.json_response({
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'active_rooms': len(rooms),
            'active_connections': len(connections)
        })

    async def join_room(self, request):
        """Join a sync room"""
        room_id = request.match_info['room_id']
        data = await request.json()

        device_id = data.get('device_id')
        device_name = data.get('device_name', 'unknown')

        if not device_id:
            return web.json_response({'error': 'device_id required'}, status=400)

        # Initialize room if it doesn't exist
        if room_id not in rooms:
            rooms[room_id] = {
                'created_at': datetime.utcnow().isoformat(),
                'devices': {},
                'message_count': 0
            }

        # Add device to room
        rooms[room_id]['devices'][device_id] = {
            'device_name': device_name,
            'last_seen': datetime.utcnow().isoformat(),
            'ip_address': request.remote
        }

        logging.info(f"Device {device_name} ({device_id}) joined room {room_id}")

        return web.json_response({
            'success': True,
            'room_id': room_id,
            'peer_count': len(rooms[room_id]['devices']) - 1
        })

    async def get_peers(self, request):
        """Get list of peers in room"""
        room_id = request.match_info['room_id']
        device_id = request.query.get('device_id')

        if room_id not in rooms:
            return web.json_response({'peers': []})

        room = rooms[room_id]
        peers = []

        for peer_id, peer_data in room['devices'].items():
            if peer_id != device_id:  # Don't include self
                # Check if peer is still active (last seen within 10 minutes)
                last_seen = datetime.fromisoformat(peer_data['last_seen'])
                if datetime.utcnow() - last_seen < timedelta(minutes=10):
                    peers.append({
                        'device_id': peer_id,
                        'device_name': peer_data['device_name'],
                        'last_seen': peer_data['last_seen']
                    })

        return web.json_response({'peers': peers})

    async def relay_sync(self, request):
        """Relay encrypted sync data between peers"""
        room_id = request.match_info['room_id']
        data = await request.json()

        from_device = data.get('from_device')
        to_devices = data.get('to_devices', [])
        encrypted_payload = data.get('encrypted_payload')

        if not all([from_device, encrypted_payload]):
            return web.json_response({'error': 'Missing required fields'}, status=400)

        if room_id not in rooms:
            return web.json_response({'error': 'Room not found'}, status=404)

        # Update sender's last seen
        if from_device in rooms[room_id]['devices']:
            rooms[room_id]['devices'][from_device]['last_seen'] = datetime.utcnow().isoformat()

        # Broadcast to specified devices or all peers
        delivered_to = []

        if to_devices:
            target_devices = to_devices
        else:
            # Broadcast to all devices in room except sender
            target_devices = [d for d in rooms[room_id]['devices'].keys() if d != from_device]

        # Store message for offline devices
        relay_message = {
            'from_device': from_device,
            'encrypted_payload': encrypted_payload,
            'timestamp': datetime.utcnow().isoformat(),
            'message_id': f"{from_device}_{int(time.time())}"
        }

        # Try to deliver via WebSocket first, fallback to storage
        for target_device in target_devices:
            if target_device in connections:
                # Real-time delivery via WebSocket
                try:
                    await connections[target_device].send_str(json.dumps(relay_message))
                    delivered_to.append(target_device)
                except Exception as e:
                    logging.warning(f"Failed to deliver to {target_device}: {e}")
            else:
                # Store for later retrieval
                if 'pending_messages' not in rooms[room_id]:
                    rooms[room_id]['pending_messages'] = {}
                if target_device not in rooms[room_id]['pending_messages']:
                    rooms[room_id]['pending_messages'][target_device] = []

                rooms[room_id]['pending_messages'][target_device].append(relay_message)

                # Limit pending messages per device
                if len(rooms[room_id]['pending_messages'][target_device]) > 50:
                    rooms[room_id]['pending_messages'][target_device] = \
                        rooms[room_id]['pending_messages'][target_device][-50:]

        rooms[room_id]['message_count'] += 1

        return web.json_response({
            'success': True,
            'delivered_to': delivered_to,
            'stored_for_offline': len(target_devices) - len(delivered_to)
        })

    async def websocket_handler(self, request):
        """WebSocket handler for real-time sync"""
        room_id = request.match_info['room_id']
        device_id = request.query.get('device_id')

        if not device_id:
            return web.Response(status=400, text='device_id required')

        ws = web.WebSocketResponse()
        await ws.prepare(request)

        # Register connection
        connections[device_id] = ws
        logging.info(f"WebSocket connected: {device_id} in room {room_id}")

        try:
            # Send any pending messages
            if room_id in rooms and 'pending_messages' in rooms[room_id]:
                pending = rooms[room_id]['pending_messages'].get(device_id, [])
                for message in pending:
                    await ws.send_str(json.dumps(message))

                # Clear pending messages
                if device_id in rooms[room_id]['pending_messages']:
                    del rooms[room_id]['pending_messages'][device_id]

            # Handle incoming messages
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                        # Handle ping/pong for keepalive
                        if data.get('type') == 'ping':
                            await ws.send_str(json.dumps({'type': 'pong'}))
                    except json.JSONDecodeError:
                        logging.warning(f"Invalid JSON from {device_id}")
                elif msg.type == WSMsgType.ERROR:
                    logging.error(f"WebSocket error for {device_id}: {ws.exception()}")

        except asyncio.CancelledError:
            pass
        finally:
            # Cleanup connection
            if device_id in connections:
                del connections[device_id]
            logging.info(f"WebSocket disconnected: {device_id}")

        return ws

    async def list_rooms(self, request):
        """Admin: List all active rooms"""
        room_list = []
        for room_id, room_data in rooms.items():
            room_list.append({
                'room_id': room_id,
                'created_at': room_data['created_at'],
                'device_count': len(room_data['devices']),
                'message_count': room_data['message_count'],
                'has_pending_messages': 'pending_messages' in room_data
            })

        return web.json_response({'rooms': room_list})

    async def get_stats(self, request):
        """Admin: Get server statistics"""
        total_devices = sum(len(room['devices']) for room in rooms.values())
        total_messages = sum(room['message_count'] for room in rooms.values())

        return web.json_response({
            'total_rooms': len(rooms),
            'total_devices': total_devices,
            'active_connections': len(connections),
            'total_messages_relayed': total_messages,
            'uptime_seconds': time.time() - start_time
        })

    async def cleanup_task(self):
        """Periodic cleanup of inactive rooms and devices"""
        while True:
            try:
                await asyncio.sleep(self.cleanup_interval)

                current_time = datetime.utcnow()
                rooms_to_remove = []

                for room_id, room_data in rooms.items():
                    devices_to_remove = []

                    # Remove inactive devices (no activity for 1 hour)
                    for device_id, device_data in room_data['devices'].items():
                        last_seen = datetime.fromisoformat(device_data['last_seen'])
                        if current_time - last_seen > timedelta(hours=1):
                            devices_to_remove.append(device_id)

                    for device_id in devices_to_remove:
                        del room_data['devices'][device_id]
                        logging.info(f"Cleaned up inactive device: {device_id}")

                    # Remove empty rooms (no devices for 24 hours)
                    if not room_data['devices']:
                        room_created = datetime.fromisoformat(room_data['created_at'])
                        if current_time - room_created > timedelta(hours=24):
                            rooms_to_remove.append(room_id)

                for room_id in rooms_to_remove:
                    del rooms[room_id]
                    logging.info(f"Cleaned up empty room: {room_id}")

            except Exception as e:
                logging.error(f"Cleanup task error: {e}")

    async def start_server(self):
        """Start the relay server"""
        # Start cleanup task
        asyncio.create_task(self.cleanup_task())

        # Start web server
        runner = web.AppRunner(self.app)
        await runner.setup()

        site = web.TCPSite(runner, self.host, self.port)
        await site.start()

        print(f"🔄 Secret Sync Relay Server running on http://{self.host}:{self.port}")
        print(f"📊 Admin panel: http://{self.host}:{self.port}/admin/stats")
        print(f"🏥 Health check: http://{self.host}:{self.port}/health")

def main():
    parser = argparse.ArgumentParser(description='Secret Sync Relay Server')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    parser.add_argument('--port', type=int, default=8080, help='Port to bind to')
    parser.add_argument('--cleanup-interval', type=int, default=300,
                       help='Cleanup interval in seconds')
    parser.add_argument('--log-level', default='INFO',
                       choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'])

    args = parser.parse_args()

    # Setup logging
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format='%(asctime)s - %(levelname)s - %(message)s'
    )

    global start_time
    start_time = time.time()

    # Create and start server
    server = SecretRelayServer(
        host=args.host,
        port=args.port,
        cleanup_interval=args.cleanup_interval
    )

    try:
        loop = asyncio.get_event_loop()
        loop.run_until_complete(server.start_server())
        loop.run_forever()
    except KeyboardInterrupt:
        print("\n👋 Shutting down relay server...")
    except Exception as e:
        logging.error(f"Server error: {e}")

if __name__ == '__main__':
    main()