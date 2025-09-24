#!/bin/bash
# Remote bootstrap script for new machines
# Usage: curl -sSL https://raw.githubusercontent.com/mikkihugo/dotfiles/main/bootstrap-remote.sh | bash
set -euo pipefail

# Auto-detect repo from curl request headers or use hardcoded default
# When downloaded via curl from GitHub raw, we know the repo structure
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:mikkihugo/dotfiles.git}"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

echo "🚀 Setting up mhugo's dotfiles on new machine..."
echo "   Repository: $DOTFILES_REPO"
echo "   Target: $DOTFILES_DIR"
echo ""

# Install Nix if not present
if ! command -v nix >/dev/null 2>&1; then
    echo "📦 Installing Nix package manager..."
    curl -L https://nixos.org/nix/install | sh -s -- --daemon

    # Source nix
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
fi

# Set up SSH keys and config
echo ""
echo "🔑 SSH Setup"
echo "============="

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "Please paste your SSH private key (from ~/.ssh/id_ed25519):"
    echo "Paste key and press Ctrl+D when done:"
    echo ""

    # Read SSH key from stdin
    cat > "$SSH_KEY_PATH"
    chmod 600 "$SSH_KEY_PATH"

    echo ""
    echo "✅ SSH private key saved to $SSH_KEY_PATH"

    # Ask for public key if not present
    if [[ ! -f "$SSH_KEY_PATH.pub" ]]; then
        echo ""
        echo "Please paste your SSH public key (from ~/.ssh/id_ed25519.pub):"
        read -r ssh_public_key
        echo "$ssh_public_key" > "$SSH_KEY_PATH.pub"
        chmod 644 "$SSH_KEY_PATH.pub"
        echo "✅ SSH public key saved to $SSH_KEY_PATH.pub"
    fi
else
    echo "✅ SSH key already exists at $SSH_KEY_PATH"
fi

# Check if user wants to add more SSH keys or config
echo ""
echo "Do you have additional SSH keys or SSH config to set up? (y/N)"
read -r setup_more_ssh

if [[ "$setup_more_ssh" =~ ^[Yy] ]]; then
    echo ""
    echo "📝 Additional SSH Setup"
    echo "You can now paste additional SSH keys or config."
    echo "Type 'done' when finished, or paste content for:"
    echo ""

    while true; do
        echo "Options:"
        echo "  1) Add another SSH private key (specify filename)"
        echo "  2) Add SSH config (~/.ssh/config)"
        echo "  3) Add known_hosts entries"
        echo "  4) Done with SSH setup"
        echo ""
        echo "Choose option (1-4):"
        read -r ssh_option

        case "$ssh_option" in
            1)
                echo "Enter filename for SSH key (e.g., id_rsa_work, id_ed25519_server):"
                read -r keyname
                keypath="$HOME/.ssh/$keyname"
                echo "Paste the private key content:"
                cat > "$keypath"
                chmod 600 "$keypath"
                echo "✅ SSH key saved to $keypath"

                echo "Paste the public key content:"
                read -r pubkey_content
                echo "$pubkey_content" > "$keypath.pub"
                chmod 644 "$keypath.pub"
                echo "✅ Public key saved to $keypath.pub"
                ;;
            2)
                echo "Paste your SSH config content:"
                cat > "$HOME/.ssh/config"
                chmod 644 "$HOME/.ssh/config"
                echo "✅ SSH config saved to ~/.ssh/config"
                ;;
            3)
                echo "Paste known_hosts entries:"
                cat >> "$HOME/.ssh/known_hosts"
                chmod 644 "$HOME/.ssh/known_hosts"
                echo "✅ Known hosts entries added"
                ;;
            4|done)
                break
                ;;
            *)
                echo "Invalid option, please try again"
                ;;
        esac
        echo ""
    done
fi

# Start SSH agent and add key
echo ""
echo "🔐 Adding SSH key to agent..."
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_PATH"

# Test SSH connection
echo "🔍 Testing SSH connection to GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ SSH connection to GitHub successful"
else
    echo "⚠️  SSH connection test failed - continuing anyway"
fi

# Clone dotfiles
echo ""
echo "📂 Cloning dotfiles repository..."
if [[ -d "$DOTFILES_DIR" ]]; then
    echo "Directory $DOTFILES_DIR already exists, updating..."
    cd "$DOTFILES_DIR"
    git pull
else
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    cd "$DOTFILES_DIR"
fi

# Enter nix develop and run install
echo ""
echo "🛠️  Entering Nix development environment..."
echo "   This will install all tools (SOPS, age, etc.) and run the installation..."
echo ""

# Use nix develop to run the installation
nix develop --command bash -c '
    echo "🔧 Setting up SOPS decryption key..."

    # Set up SOPS age key
    SOPS_KEY_DIR="$HOME/.config/sops/age"
    SOPS_KEY_FILE="$SOPS_KEY_DIR/keys.txt"
    mkdir -p "$SOPS_KEY_DIR"

    # Generate age key from SSH key
    ssh-to-age -private-key -i ~/.ssh/id_ed25519 > "$SOPS_KEY_FILE"
    chmod 600 "$SOPS_KEY_FILE"
    echo "✅ SOPS age key created"

    # Test SOPS decryption
    if [[ -f "secrets/shared.yaml" ]] && sops -d "secrets/shared.yaml" >/dev/null 2>&1; then
        echo "✅ SOPS decryption test successful"
        echo "🎉 All secrets are now accessible!"
    else
        echo "⚠️  No secrets file found or decryption failed"
        echo "   You may need to create secrets/shared.yaml"
    fi

    # Run the installation
    echo ""
    echo "🏗️  Running dotfiles installation..."
    ./install.sh

    echo ""
    echo "✅ Installation complete!"
    echo ""
    echo "🎉 Your new machine is ready!"
    echo "   Start a new shell to load all environment variables"
    echo ""
    echo "Next steps:"
    echo "  • Open a new terminal to test everything"
    echo "  • Run: echo \$GITHUB_TOKEN  (should show your token)"
    echo "  • Run: gh auth status      (should show authenticated)"
'

echo ""
echo "🎉 Bootstrap complete! Welcome to your new machine!"
echo ""
echo "💡 Pro tip: Add this to your new machine checklist:"
echo "   curl -sSL https://raw.githubusercontent.com/mikkihugo/dotfiles/main/bootstrap-remote.sh | bash"