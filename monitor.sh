#!/bin/bash

# Function to detect Linux distribution
detect_distro() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Function to check for system updates
check_updates() {
    echo -e "\n Updates Available:"
    DISTRO=$(detect_distro)
    
    if [ "$DISTRO" == "arch" ]; then
        echo "  Arch Linux detected - checking with pacman"
        updates=$(pacman -Qu | wc -l)
        if [ "$updates" -eq 0 ]; then
            echo "  No updates available"
        else
            echo "  $updates updates available"
            echo "  Run 'sudo pacman -Syu' to update your system"
        fi
    elif [ "$DISTRO" == "debian" ]; then
        echo "  Debian-based system detected"
        if ! apt-get update -qq > /dev/null; then
            echo "  Error checking for updates. Try running 'sudo apt update' manually."
        else
            updates=$(apt-get -s upgrade | grep -c ^Inst)
            if [ "$updates" -eq 0 ]; then
                echo "  No updates available"
            else
                echo "  $updates updates available"
                echo "  Run 'sudo apt update && sudo apt upgrade' to update your system"
            fi
        fi
    else
        echo "  Unsupported distribution. Only Arch and Debian-based systems are supported."
    fi
}

# Function to display active network connections
show_network() {
    echo -e "\n Network Connections:"
    # Get the interface with default route (internet source)
    DEFAULT_ROUTE=$(ip route get 8.8.8.8 2>/dev/null | head -n1 | awk '{print $5}')
    
    if [ -n "$DEFAULT_ROUTE" ]; then
        IP_ADDR=$(ip -br addr show "$DEFAULT_ROUTE" | awk '{print $3}')
        echo "  Active Internet Interface: $DEFAULT_ROUTE ($IP_ADDR)"
        
        # Check if it's a wireless interface and display SSID if it is
        if [[ "$DEFAULT_ROUTE" == wl* ]]; then
            SSID=$(iwconfig "$DEFAULT_ROUTE" 2>/dev/null | grep ESSID | awk -F: '{print $2}' | tr -d '"' | xargs)
            if [ -n "$SSID" ]; then
                echo "  Connected to Wi-Fi network: $SSID"
            else
                echo "  Wireless interface detected, but SSID information not available"
            fi
        fi
    else
        echo "  No active internet connection detected"
        # Fallback to show any UP interface
        ip -br addr show | grep "UP" | head -n1 | awk '{print "  Active Interface: " $1 ": " $3}'
    fi
}

# Function to list recently modified files in home
recent_files() {
    echo -e "\n Files Modified in Last 24 Hours:"
    for dir in "Desktop" "Documents" "Downloads" "Photos" "Pictures" "Videos"; do
        if [ -d "$HOME/$dir" ]; then
            echo "  In ~/$dir:"
            find "$HOME/$dir" -type f -mtime -1 2>/dev/null | head -n 3 | while read file; do
                echo "    $(ls -lh "$file" | awk '{print $5, $6, $7, $8}') - $(basename "$file")"
            done
            COUNT=$(find "$HOME/$dir" -type f -mtime -1 2>/dev/null | wc -l)
            if [ "$COUNT" -gt 3 ]; then
                echo "    ... and $(($COUNT - 3)) more files"
            elif [ "$COUNT" -eq 0 ]; then
                echo "    No recent files"
            fi
        fi
    done
}

# Function to create backups
create_backup() {
    DRYRUN=$1
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="$HOME/backups_$TIMESTAMP"
    
    # Calculate the space needed for backup and available disk space
    echo -e "\n Backup Disk Space Analysis:"
    TOTAL_SIZE=0
    for dir in "Documents" "Desktop" "Pictures" "Videos"; do
        if [ -d "$HOME/$dir" ]; then
            DIR_SIZE=$(du -sk "$HOME/$dir" 2>/dev/null | cut -f1)
            TOTAL_SIZE=$((TOTAL_SIZE + DIR_SIZE))
            SIZE_HUMAN=$(du -sh "$HOME/$dir" 2>/dev/null | cut -f1)
            echo "  $HOME/$dir size: $SIZE_HUMAN"
        fi
    done
    
    # Convert to human-readable format
    TOTAL_SIZE_HUMAN=$(echo "$TOTAL_SIZE" | awk '{hr = $1/1024; printf("%.1f GB", hr/1024)}')
    echo "  Total backup size: $TOTAL_SIZE_HUMAN"
    
    # Get available space on the destination drive
    DEST_DRIVE=$(df -P "$HOME" | awk 'NR==2 {print $1}')
    AVAIL_SPACE=$(df -P "$HOME" | awk 'NR==2 {print $4}')
    AVAIL_SPACE_HUMAN=$(df -Ph "$HOME" | awk 'NR==2 {print $4}')
    echo "  Available space: $AVAIL_SPACE_HUMAN on $DEST_DRIVE"
    
    # Check if we have enough space (with 10% margin)
    NEEDED_SPACE=$((TOTAL_SIZE * 110 / 100))
    if [ "$AVAIL_SPACE" -lt "$NEEDED_SPACE" ]; then
        echo "  WARNING: Not enough disk space for backup!"
        echo "  Required (with 10% margin): $(echo "$NEEDED_SPACE" | awk '{hr = $1/1024; printf("%.1f GB", hr/1024)}')"
        
        # If not a dry run, abort due to insufficient space
        if [ "$DRYRUN" = false ]; then
            echo "  Backup aborted due to insufficient disk space."
            return 1
        fi
    else
        echo "  Sufficient disk space available for backup."
    fi
    
    if [ "$DRYRUN" = true ]; then
        echo -e "\n Backup Utility (Dry Run):"
        echo "  DRY RUN MODE - No actual backup will be created"
        
        for dir in "Documents" "Desktop" "Pictures" "Videos"; do
            if [ -d "$HOME/$dir" ]; then
                SOURCE="$HOME/$dir"
                DEST="$BACKUP_DIR/$dir"
                SIZE=$(du -sh "$SOURCE" 2>/dev/null | cut -f1)
                echo "  Would backup: $SOURCE ($SIZE) to $DEST"
            else
                echo "  Directory $HOME/$dir not found, skipping"
            fi
        done
    else
        echo -e "\n Backup Utility:"
        echo "  Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        
        for dir in "Documents" "Desktop" "Pictures" "Videos"; do
            if [ -d "$HOME/$dir" ]; then
                SOURCE="$HOME/$dir"
                DEST="$BACKUP_DIR/$dir"
                SIZE=$(du -sh "$SOURCE" 2>/dev/null | cut -f1)
                echo "  Backing up: $SOURCE ($SIZE) to $DEST"
                mkdir -p "$DEST"
                cp -r "$SOURCE"/* "$DEST" 2>/dev/null || echo "  Warning: Some files in $SOURCE could not be copied"
            else
                echo "  Directory $HOME/$dir not found, skipping"
            fi
        done
        echo "  Backup completed to: $BACKUP_DIR"
    fi
}

# Check if fastfetch is installed
if ! command -v fastfetch &> /dev/null; then
    echo "fastfetch is not installed. Please install it first."
    echo "You can install it with: sudo apt install fastfetch (for Debian/Ubuntu)"
    echo "Or check: https://github.com/fastfetch-cli/fastfetch for other methods."
    exit 1
fi

# Clear screen and display fastfetch
clear
echo "=== System Information ==="
fastfetch

echo ""
echo "=== Detailed System Monitoring ==="

# CPU usage
echo -e "\n CPU Usage:"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "  Current usage: " (100 - $1) "%"}'

# RAM usage
echo -e "\n Memory Usage:"
free -m | awk 'NR==2{printf "  Used: %s MB / Total: %s MB (%.2f%%)\n", $3, $2, $3*100/$2}'

# Disk usage
echo -e "\n Disk Usage:"
df -h | grep "^/dev" | awk '{print "  " $1 " - Used: " $3 " / Total: " $2 " (" $5 ") - Mounted on: " $6}'

# Run all utility functions automatically
check_updates
show_network
recent_files

# Check for command line argument to control dry run mode
if [ "$1" = "--backup" ]; then
    # Run actual backup when --backup flag is provided
    create_backup false
else
    # Default to dry run mode for safety
    create_backup true
fi

echo -e "\n=== End of System Monitor ==="