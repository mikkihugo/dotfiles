# Tabby Gateway Configuration

## Gateway Details
- **Token**: `YOUR_GATEWAY_TOKEN`
- **Port**: 9000
- **Container**: tabby-gateway

## Deployment
```bash
~/.dotfiles/.scripts/deploy-tabby-gateway.sh
```

## Access URLs
- **Gateway**: `ws://YOUR_SERVER_IP:9000`
- **With SSL**: `wss://YOUR_DOMAIN:9000`

## Tabby Web Configuration
1. Deploy Tabby Web (separate container)
2. Set environment variable: `TABBY_CONNECTION_GATEWAY=ws://gateway:9000`
3. Configure OAuth providers for authentication

## Team Usage
1. Share the gateway URL and token with team
2. Each user configures their Tabby to use the gateway
3. All SSH connections go through the central gateway

## Security Notes
- Change token in production
- Use SSL/TLS for internet-facing deployments
- Consider firewall rules to restrict access