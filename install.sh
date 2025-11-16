#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Package info
PACKAGE_NAME="Raptor"
PACKAGE_VERSION="1.3.0"
INSTALL_DIR="/opt/raptor"
BASE_URL="https://amirvali.ir/raptor"

# Output functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get current user (not root)
get_current_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$(whoami)"
    fi
}

# Check if running with sudo
check_sudo() {
    if [[ $EUID -eq 0 ]] && [ -z "$SUDO_USER" ]; then
        print_error "Do not run as root directly. Use: sudo bash install.sh"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking system prerequisites..."
    
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        print_error "Please install curl or wget"
        exit 1
    fi
    
    if ! command -v systemctl >/dev/null 2>&1; then
        print_error "systemd not found"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Download file from server
download_file() {
    local file_url="$1"
    local output_file="$2"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -f -L "$file_url" -o "$output_file" 2>/dev/null
    else
        wget -q "$file_url" -O "$output_file" 2>/dev/null
    fi
}

# Generate system fingerprint
generate_fingerprint() {
    local fingerprint=""
    
    # Use machine-id if available
    if [[ -f /etc/machine-id ]]; then
        fingerprint=$(cat /etc/machine-id | head -c 16)
    else
        # Fallback: use hostname + timestamp hash
        local hostname=$(hostname)
        local timestamp=$(date +%s)
        fingerprint=$(echo "${hostname}-${timestamp}" | sha256sum | head -c 16)
    fi
    
    echo "host-${fingerprint}"
}

# Create installation directory and hostname file
setup_installation() {
    print_info "Setting up installation directory..."
    
    # Create installation directory
    sudo mkdir -p "$INSTALL_DIR"
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "Failed to create installation directory: $INSTALL_DIR"
        exit 1
    fi
    
    # Generate fingerprint
    local fingerprint=$(generate_fingerprint)
    
    # Create hostname file
    echo "$fingerprint" | sudo tee "$INSTALL_DIR/hostname" > /dev/null
    
    # Verify file creation
    if [[ -f "$INSTALL_DIR/hostname" ]] && [[ -s "$INSTALL_DIR/hostname" ]]; then
        local saved_fingerprint=$(cat "$INSTALL_DIR/hostname")
        print_success "Hostname file created: $saved_fingerprint"
        echo "$saved_fingerprint"
    else
        print_error "Failed to create hostname file"
        exit 1
    fi
}

# Register system with server
register_system() {
    local fingerprint="$1"
    local hostname=$(hostname)
    local os_info=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    local current_user=$(get_current_user)
    
    print_info "Registering system with Raptor server..."
    
    # Send registration to server
    if command -v curl >/dev/null 2>&1; then
        if curl -s -f -X POST \
           --data-urlencode "fingerprint=$fingerprint" \
           --data-urlencode "hostname=$hostname" \
           --data-urlencode "os=$os_info" \
           --data-urlencode "user=$current_user" \
           "$BASE_URL/register.php" > /dev/null 2>&1; then
            print_success "System registered successfully: $fingerprint"
            return 0
        fi
    else
        if wget -q --post-data="fingerprint=$fingerprint&hostname=$hostname&os=$os_info&user=$current_user" \
           "$BASE_URL/register.php" -O /dev/null 2>&1; then
            print_success "System registered successfully: $fingerprint"
            return 0
        fi
    fi
    
    print_warning "Registration failed, but installation will continue"
    return 1
}

# Download all required files
download_files() {
    print_info "Downloading Raptor files..."
    
    local files=("raptor.sh" "raptor.service" "config.conf")
    
    for file in "${files[@]}"; do
        print_info "Downloading $file..."
        
        if ! download_file "$BASE_URL/$file" "/tmp/$file"; then
            print_error "Failed to download $file"
            return 1
        fi
        
        # Copy to installation directory
        sudo cp "/tmp/$file" "$INSTALL_DIR/$file"
        
        if [[ "$file" == "raptor.sh" ]]; then
            sudo chmod +x "$INSTALL_DIR/$file"
        fi
    done
    
    print_success "All files downloaded successfully"
    return 0
}

# Create systemd service for current user
create_user_service() {
    local current_user=$(get_current_user)
    local user_id=$(id -u "$current_user")
    
    print_info "Creating systemd service for user: $current_user"
    
    # Create user systemd directory
    sudo mkdir -p "/home/$current_user/.config/systemd/user"
    
    # Create user service file
    sudo tee "/home/$current_user/.config/systemd/user/raptor.service" > /dev/null <<EOF
[Unit]
Description=Raptor Command Runner Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/raptor.sh
Restart=always
RestartSec=10
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=default.target
EOF

    # Enable lingering for user service
    sudo loginctl enable-linger "$current_user"
    
    # Start user service
    sudo -u "$current_user" XDG_RUNTIME_DIR=/run/user/$user_id systemctl --user enable raptor.service
    sudo -u "$current_user" XDG_RUNTIME_DIR=/run/user/$user_id systemctl --user start raptor.service
    
    print_success "User service created and started"
}

# Configure package
configure_package() {
    print_info "Configuring Raptor..."
    
    local current_user=$(get_current_user)
    
    # Create log file
    sudo touch "/var/log/raptor.log"
    sudo chown "$current_user:$current_user" "/var/log/raptor.log"
    sudo chmod 644 "/var/log/raptor.log"
    
    # Set permissions on installation directory
    sudo chown -R "$current_user:$current_user" "$INSTALL_DIR"
    sudo chmod -R 755 "$INSTALL_DIR"
    sudo chmod 600 "$INSTALL_DIR/config.conf"
    sudo chmod 600 "$INSTALL_DIR/hostname"
    
    print_success "Configuration completed"
}

# Main installation function
main() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════╗"
    echo "║           Raptor Installer           ║"
    echo "║           Version $PACKAGE_VERSION           ║"
    echo "║         (User Mode Edition)          ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
    
    print_info "Starting Raptor $PACKAGE_VERSION installation"
    
    check_sudo
    check_prerequisites
    
    # Setup installation first (creates directory and hostname file)
    local fingerprint=$(setup_installation)
    
    if ! download_files; then
        print_error "Failed to download files from server"
        exit 1
    fi
    
    register_system "$fingerprint"
    
    if ! configure_package; then
        print_error "Configuration failed"
        exit 1
    fi
    
    create_user_service
    
    echo
    print_success "Raptor installation completed successfully"
    echo
    echo -e "${GREEN}System Registered As:${NC}"
    echo -e "  • Host Identifier: ${fingerprint}"
    echo -e "  • Running as user: $(get_current_user)"
    echo
    echo -e "${GREEN}Installation Details:${NC}"
    echo -e "  • Install Directory: ${INSTALL_DIR}"
    echo -e "  • Log File: /var/log/raptor.log"
    echo -e "  • Service Type: User systemd service"
    echo
    echo -e "${GREEN}Management Commands:${NC}"
    echo -e "  • Check status: ${YELLOW}systemctl --user status raptor.service${NC}"
    echo -e "  • View logs: ${YELLOW}tail -f /var/log/raptor.log${NC}"
    echo -e "  • Check hostname: ${YELLOW}cat ${INSTALL_DIR}/hostname${NC}"
}

# Run main function
main "$@"