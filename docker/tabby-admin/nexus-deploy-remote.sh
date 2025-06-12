#!/bin/bash
#
# Deploy Nexus for Remote Access
# Purpose: Deploy with proper remote access configuration
# Version: 1.0.0

set -euo pipefail

# Get server IP
SERVER_IP=$(curl -s https://ifconfig.me)
INTERNAL_IP=$(hostname -I | awk '{print $1}')

echo "🌐 Configuring Nexus for remote access"
echo "Server Public IP: $SERVER_IP"
echo "Server Internal IP: $INTERNAL_IP"
echo ""

# Option 1: SSH Tunnel (Recommended)
setup_ssh_tunnel() {
    echo "📡 SSH Tunnel Setup (Recommended)"
    echo "================================"
    echo ""
    echo "From your local machine, run:"
    echo ""
    echo "ssh -L 10080:localhost:10080 \\"
    echo "    -L 10888:localhost:10888 \\"
    echo "    -L 10200:localhost:10200 \\"
    echo "    $(whoami)@$SERVER_IP"
    echo ""
    echo "Then access:"
    echo "  • VS Code: http://localhost:10080"
    echo "  • Jupyter: http://localhost:10888"
    echo "  • Vault:   http://localhost:10200"
    echo ""
}

# Option 2: Cloudflare Tunnel
setup_cloudflare_tunnel() {
    echo "☁️  Cloudflare Tunnel Setup"
    echo "========================"
    
    if [ -z "${CF_API_TOKEN:-}" ]; then
        echo "❌ No CF_API_TOKEN found"
        echo "Set: export CF_API_TOKEN=your_token"
        return 1
    fi
    
    # Use the nexus-unpacker script
    cd $(dirname "$0")
    ./nexus-unpacker.sh deploy
}

# Option 3: Tailscale (Zero-config VPN)
setup_tailscale() {
    echo "🔐 Tailscale Setup (Easy VPN)"
    echo "============================"
    
    # Check if Tailscale is installed
    if ! command -v tailscale &>/dev/null; then
        echo "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Start Tailscale
    sudo tailscale up
    
    # Get Tailscale IP
    TAILSCALE_IP=$(tailscale ip -4)
    echo "Tailscale IP: $TAILSCALE_IP"
    echo ""
    echo "Access via Tailscale network:"
    echo "  • VS Code: http://$TAILSCALE_IP:10080"
    echo "  • Jupyter: http://$TAILSCALE_IP:10888"
    echo "  • Vault:   http://$TAILSCALE_IP:10200"
}

# Option 4: Direct IP (Less Secure)
setup_direct_ip() {
    echo "⚠️  Direct IP Access (Less Secure)"
    echo "================================"
    echo ""
    echo "This will expose services on public IP!"
    echo "Continue? (y/N)"
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    # Create override compose file
    cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  ai:
    ports:
      - "0.0.0.0:10080:8080"  # Bind to all interfaces
      - "0.0.0.0:10888:8888"
      - "0.0.0.0:13000:3000"
    environment:
      - CODE_SERVER_HOST=0.0.0.0  # Allow external access
      
  vault:
    ports:
      - "0.0.0.0:10200:8200"
EOF
    
    echo "Access directly at:"
    echo "  • VS Code: http://$SERVER_IP:10080"
    echo "  • Jupyter: http://$SERVER_IP:10888"
    echo "  • Vault:   http://$SERVER_IP:10200"
    echo ""
    echo "⚠️  Remember to configure firewall!"
}

# Main menu
echo "Choose access method:"
echo "1) SSH Tunnel (Most Secure)"
echo "2) Cloudflare Tunnel (No Ports)"
echo "3) Tailscale VPN (Easy Setup)"
echo "4) Direct IP (Less Secure)"
echo ""
read -p "Choice (1-4): " choice

case $choice in
    1) setup_ssh_tunnel ;;
    2) setup_cloudflare_tunnel ;;
    3) setup_tailscale ;;
    4) setup_direct_ip ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

# Create convenience script
cat > ~/nexus-connect.sh << 'EOF'
#!/bin/bash
# Quick connect to Nexus services

SERVER_IP="${1:-$(cat ~/.nexus-server-ip 2>/dev/null)}"

if [ -z "$SERVER_IP" ]; then
    echo "Usage: $0 server-ip"
    echo "Or save IP: echo 'your-server-ip' > ~/.nexus-server-ip"
    exit 1
fi

echo "Connecting to Nexus at $SERVER_IP..."
ssh -L 10080:localhost:10080 \
    -L 10888:localhost:10888 \
    -L 10200:localhost:10200 \
    "$SERVER_IP"
EOF
chmod +x ~/nexus-connect.sh

echo ""
echo "✅ Setup complete!"
echo "Quick connect script created: ~/nexus-connect.sh"