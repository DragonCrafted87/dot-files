#!/bin/bash

# Initialization script for setting up bash environment, system configs, SSH access, and oh-my-posh on openSUSE Leap
# Run as the 'dragon' user with sudo privileges

# Exit on error
set -e

# Variables
REPO_URL="git@github.com:DragonCrafted87/dot-files.git"
GITHUB_USER="DragonCrafted87"
GITHUB_KEYS_URL="https://github.com/$GITHUB_USER.keys"
HOME_DIR="/home/dragon"
REPO_DIR="$HOME_DIR/dot-files"
BASHRC_SRC="$REPO_DIR/hw_bashrc.sh"
BASHRC_DIR_SRC="$REPO_DIR/bashrc.d"
BASHRC_DEST="$HOME_DIR/.bashrc"
BASHRC_DIR_DEST="$HOME_DIR/.bashrc.d"
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
SSH_CONFIG="$SSH_DIR/config"
SUDOERS_FILE="/etc/sudoers.d/dragon"
TIMEZONE="America/Chicago"
OH_MY_POSH_PATH="/usr/local/bin/oh-my-posh"

# Check if running as the 'dragon' user and not root
if [ "$(id -u)" -eq 0 ] || [ "$(whoami)" != "dragon" ]; then
    echo "Error: This script must be run as the 'dragon' user, not as root or another user."
    exit 1
fi

# Check if zypper is available for package installation
if ! command -v zypper &> /dev/null; then
    echo "Error: zypper is not installed. Cannot install required commands."
    exit 1
fi

# Ensure required commands are installed
for cmd in git sudo ln rm timedatectl curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "$cmd is not installed. Attempting to install..."
        sudo zypper install -y "$cmd" || {
            echo "Error: Failed to install $cmd. Please install it manually."
            exit 1
        }
    fi
    echo "$cmd is available"
done

# Set up sudoers entry for user 'dragon'
echo "Setting up sudoers entry for dragon..."
sudo sh -c "echo 'dragon ALL=(ALL) NOPASSWD: ALL' > '$SUDOERS_FILE'" && \
sudo chmod 440 "$SUDOERS_FILE" && \
echo "Sudoers entry created at $SUDOERS_FILE"

# Set up SSH configuration for GitHub
echo "Setting up SSH configuration for GitHub..."

# Create .ssh directory if it doesn't exist
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    echo "Created $SSH_DIR with correct permissions"
fi

# Check for existing SSH key pair
if [ ! -f "$SSH_DIR/id_ed25519" ] && [ ! -f "$SSH_DIR/id_rsa" ]; then
    echo "No SSH key pair found. Generating a new ed25519 key pair..."
    ssh-keygen -t ed25519 -C "$GITHUB_USER@opensuse" -f "$SSH_DIR/id_ed25519" -N ""
    echo "SSH key pair generated at $SSH_DIR/id_ed25519"
    echo "Please add the following public key to your GitHub account at https://github.com/settings/keys:"
    cat "$SSH_DIR/id_ed25519.pub"
    echo -n "Press Enter to continue after adding the key to GitHub..."
    read -r
fi

# Configure SSH client for GitHub
if [ ! -f "$SSH_CONFIG" ] || ! grep -q "Host github.com" "$SSH_CONFIG"; then
    cat << EOF >> "$SSH_CONFIG"
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_DIR/id_ed25519
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_CONFIG"
    echo "Configured SSH client for GitHub in $SSH_CONFIG"
else
    echo "SSH configuration for GitHub already exists in $SSH_CONFIG"
fi

# Test SSH connection to GitHub
echo "Testing SSH connection to GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "Hi $GITHUB_USER"; then
    echo "SSH connection to GitHub successful"
else
    echo "Error: SSH connection test to GitHub failed. Please verify your SSH key is added to GitHub."
    exit 1
fi

# Clone or update the dot-files repository
if [ -d "$REPO_DIR" ]; then
    echo "Repository already exists. Pulling latest changes..."
    cd "$REPO_DIR" && git pull
else
    echo "Cloning dot-files repository..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Remove existing .bashrc and .bashrc.d if they exist
[ -f "$BASHRC_DEST" ] && rm -f "$BASHRC_DEST" && echo "Removed existing $BASHRC_DEST"
[ -d "$BASHRC_DIR_DEST" ] && rm -rf "$BASHRC_DIR_DEST" && echo "Removed existing $BASHRC_DIR_DEST"

# Create symbolic links for .bashrc and .bashrc.d
ln -sf "$BASHRC_SRC" "$BASHRC_DEST" && echo "Linked $BASHRC_SRC to $BASHRC_DEST"
ln -sf "$BASHRC_DIR_SRC" "$BASHRC_DIR_DEST" && echo "Linked $BASHRC_DIR_SRC to $BASHRC_DIR_DEST"

# Set up oh-my-posh
if [ ! -x "$OH_MY_POSH_PATH" ]; then
    echo "Installing oh-my-posh..."
    sudo curl -fsSL https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -o "$OH_MY_POSH_PATH" || {
        echo "Error: Failed to download oh-my-posh"
        exit 1
    }
    sudo chmod +x "$OH_MY_POSH_PATH"
    echo "oh-my-posh installed at $OH_MY_POSH_PATH"
else
    echo "oh-my-posh is already installed at $OH_MY_POSH_PATH"
fi

# Set up root's bash environment
echo "Configuring root's bash environment..."
sudo rm -f /root/.bashrc /root/.bashrc.d
sudo ln -sf "$BASHRC_DEST" /root/.bashrc && echo "Linked $BASHRC_DEST to /root/.bashrc"
sudo ln -sf "$BASHRC_DIR_DEST" /root/.bashrc.d && echo "Linked $BASHRC_DIR_DEST to /root/.bashrc.d"

# Set system timezone
echo "Setting timezone to $TIMEZONE..."
sudo timedatectl set-timezone "$TIMEZONE"

# Create symbolic link for python3 to python
if [ -x /usr/bin/python3 ] && [ ! -e /usr/bin/python ]; then
    echo "Creating symbolic link for python3 to python..."
    sudo ln -sf /usr/bin/python3 /usr/bin/python
else
    echo "Skipping python link: /usr/bin/python3 not found or /usr/bin/python already exists"
fi

# Fetch and append GitHub public keys to authorized_keys
echo "Fetching GitHub public keys for $GITHUB_USER..."
KEYS=$(curl -fsSL "$GITHUB_KEYS_URL" 2>/dev/null) || {
    echo "Error: Failed to fetch public keys from $GITHUB_KEYS_URL"
    exit 1
}

# Validate that the response contains valid SSH public keys
if [ -z "$KEYS" ]; then
    echo "Error: No public keys found for $GITHUB_USER"
    exit 1
fi

# Check if keys are in valid OpenSSH format
echo "$KEYS" | while IFS= read -r key; do
    if [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp521) ]]; then
        echo "Valid key found: ${key:0:20}..."
    else
        echo "Error: Invalid SSH key format detected in fetched keys: $key"
        exit 1
    fi
done

# Append keys to authorized_keys, avoiding duplicates
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
while IFS= read -r key; do
    if [ -n "$key" ] && ! grep -Fx "$key" "$AUTH_KEYS" > /dev/null; then
        echo "$key" >> "$AUTH_KEYS"
        echo "Added key to $AUTH_KEYS: ${key:0:20}..."
    fi
done <<< "$KEYS"

echo "Initialization complete. Please log out and back in or source ~/.bashrc to apply changes."
