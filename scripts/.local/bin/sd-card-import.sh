#!/bin/bash
# SD Card Photo Import Script with ncurses TUI
# Detects SD card, asks user preferences, and organizes photos by EXIF date

set -uo pipefail

# Default import directory
DEFAULT_IMPORT_DIR="$HOME/Pictures/Input"

# Function to find SD card mount point
find_sd_card() {
    # Try to find mounted SD card
    # Common mount points: /media, /run/media, /mnt
    for mount_dir in /media /run/media /mnt; do
        if [ -d "$mount_dir" ]; then
            # Look for mounted devices (excluding system mounts)
            for device in "$mount_dir"/*; do
                if [ -d "$device" ] && [ -r "$device" ]; then
                    # Check if it looks like an SD card (has DCIM folder or common photo extensions)
                    if [ -d "$device/DCIM" ] || find "$device" -maxdepth 2 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.raw" -o -iname "*.cr2" -o -iname "*.nef" -o -iname "*.arw" \) 2>/dev/null | head -1 | grep -q .; then
                        echo "$device"
                        return 0
                    fi
                fi
            done
        fi
    done
    return 1
}

# Function to ask user for file type preference (ncurses)
ask_file_type() {
    local choice
    choice=$(dialog --clear --stdout \
        --title "SD Card Photo Import" \
        --menu "Select file types to import:" \
        12 50 3 \
        1 "JPEGs only" \
        2 "RAW files only" \
        3 "Both JPEGs and RAW files")
    
    case "$choice" in
        1)
            FILE_TYPES="JPEGs"
            ;;
        2)
            FILE_TYPES="RAW files"
            ;;
        3)
            FILE_TYPES="JPEGs and RAW files"
            ;;
        *)
            # User cancelled or invalid
            return 1
            ;;
    esac
    return 0
}

# Function to ask for import directory (ncurses)
ask_import_directory() {
    local import_dir
    import_dir=$(dialog --clear --stdout \
        --title "SD Card Photo Import" \
        --inputbox "Enter import directory:" \
        10 60 \
        "$DEFAULT_IMPORT_DIR")
    
    if [ -z "$import_dir" ]; then
        import_dir="$DEFAULT_IMPORT_DIR"
    fi
    
    # Expand ~ and create directory if it doesn't exist
    import_dir="${import_dir/#\~/$HOME}"
    mkdir -p "$import_dir"
    echo "$import_dir"
}

# Function to get EXIF date from file
get_exif_date() {
    local file="$1"
    
    # Try DateTimeOriginal first (most accurate)
    local date=$(exiftool -s3 -DateTimeOriginal -d "%Y %m" "$file" 2>/dev/null | head -1)
    if [ -n "$date" ] && [ "$date" != "-" ] && [ "${date:0:4}" != "----" ]; then
        echo "$date"
        return 0
    fi
    
    # Fallback to FileModifyDate
    date=$(exiftool -s3 -FileModifyDate -d "%Y %m" "$file" 2>/dev/null | head -1)
    if [ -n "$date" ] && [ "$date" != "-" ] && [ "${date:0:4}" != "----" ]; then
        echo "$date"
        return 0
    fi
    
    # Fallback to file modification date
    if [ -f "$file" ]; then
        local file_date=$(stat -c "%y" "$file" 2>/dev/null || stat -f "%Sm" -t "%Y %m" "$file" 2>/dev/null)
        if [ -n "$file_date" ]; then
            # Parse date format: "2025-11-18 22:46:05.146531958 +0200" -> "2025 11"
            echo "$file_date" | awk '{split($1, d, "-"); print d[1], d[2]}'
            return 0
        fi
    fi
    
    # Last resort: use current date
    date +"%Y %m"
}

# Function to find and copy files with progress
import_files() {
    local source_dir="$1"
    local dest_base="$2"
    
    # Build find conditions directly
    local find_args=()
    case "$FILE_TYPES" in
        "JPEGs")
            find_args=(-iname "*.jpg" -o -iname "*.jpeg")
            ;;
        "RAW files")
            find_args=(-iname "*.raw" -o -iname "*.cr2" -o -iname "*.nef" -o -iname "*.arw" -o -iname "*.dng" -o -iname "*.raf" -o -iname "*.orf")
            ;;
        "JPEGs and RAW files")
            find_args=(-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.raw" -o -iname "*.cr2" -o -iname "*.nef" -o -iname "*.arw" -o -iname "*.dng" -o -iname "*.raf" -o -iname "*.orf")
            ;;
    esac
    
    # Count total files first
    local total_files=0
    while IFS= read -r -d '' file; do
        total_files=$((total_files + 1))
    done < <(find "$source_dir" -type f \( "${find_args[@]}" \) -print0 2>/dev/null)
    
    if [ "$total_files" -eq 0 ]; then
        dialog --clear --title "Import Complete" \
            --msgbox "No matching files found on SD card." 8 50
        return 1
    fi
    
    # Find all matching files and process
    local files_found=0
    local files_copied=0
    local files_skipped=0
    local current_file=0
    
    # Create temp file for progress
    local progress_file=$(mktemp)
    
    while IFS= read -r -d '' file; do
        files_found=$((files_found + 1))
        current_file=$((current_file + 1))
        current_percent=$((current_file * 100 / total_files))
        
        # Update progress
        {
            echo "XXX"
            echo "$current_percent"
            echo "Processing: $(basename "$file")"
            echo "XXX"
        } | dialog --clear --title "Importing Photos" --gauge "Processing files..." 10 60 0
        
        # Get EXIF date
        local date_info=$(get_exif_date "$file")
        local year=$(echo "$date_info" | awk '{print $1}')
        local month=$(echo "$date_info" | awk '{print $2}')
        
        # Validate year and month
        if [ -z "$year" ] || [ -z "$month" ] || ! [[ "$year" =~ ^[0-9]{4}$ ]] || ! [[ "$month" =~ ^[0-9]{1,2}$ ]]; then
            year=$(date +"%Y")
            month=$(date +"%m")
        fi
        
        # Format month with leading zero if needed
        month=$(printf "%02d" "$month")
        
        # Create directory structure: YEAR/YEAR-MONTH
        local dest_dir="$dest_base/$year/$year-$month"
        mkdir -p "$dest_dir"
        
        # Get filename
        local filename=$(basename "$file")
        local dest_file="$dest_dir/$filename"
        
        # Check if file already exists
        if [ -f "$dest_file" ]; then
            # Compare file sizes
            local src_size=$(stat -c "%s" "$file" 2>/dev/null || stat -f "%z" "$file" 2>/dev/null || echo "0")
            local dest_size=$(stat -c "%s" "$dest_file" 2>/dev/null || stat -f "%z" "$dest_file" 2>/dev/null || echo "0")
            
            if [ "$src_size" = "$dest_size" ] && [ "$src_size" != "0" ]; then
                files_skipped=$((files_skipped + 1))
                continue
            fi
        fi
        
        # Copy file
        if cp "$file" "$dest_file" 2>/dev/null; then
            files_copied=$((files_copied + 1))
        fi
        
    done < <(find "$source_dir" -type f \( "${find_args[@]}" \) -print0 2>/dev/null)
    
    # Clean up progress file
    rm -f "$progress_file"
    
    # Show results
    local result_msg="Import complete!\n\n"
    result_msg+="Files found: $files_found\n"
    result_msg+="Files copied: $files_copied\n"
    result_msg+="Files skipped: $files_skipped"
    
    dialog --clear --title "Import Complete" \
        --msgbox "$result_msg" 10 50
}

# Function to unmount SD card
unmount_card() {
    local mount_point="$1"
    
    # Try to find the device
    local device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null || mount | grep "$mount_point" | awk '{print $1}')
    
    if [ -n "$device" ]; then
        # Try unmount
        if umount "$mount_point" 2>/dev/null; then
            dialog --clear --title "Unmount" \
                --msgbox "SD card unmounted successfully" 8 50
        else
            dialog --clear --title "Unmount Warning" \
                --msgbox "Could not unmount $mount_point\n\nYou may need to unmount it manually." 10 50
        fi
    else
        dialog --clear --title "Unmount Warning" \
            --msgbox "Could not determine device for $mount_point" 8 50
    fi
}

# Main execution
main() {
    # Check if dialog is available
    if ! command -v dialog >/dev/null 2>&1; then
        echo "Error: dialog is required for this script"
        echo "Install it with: sudo pacman -S dialog"
        exit 1
    fi
    
    # Find SD card
    local SD_CARD
    SD_CARD=$(find_sd_card)
    
    if [ -z "$SD_CARD" ]; then
        dialog --clear --title "Error" \
            --msgbox "No SD card detected!\n\nPlease insert an SD card and try again." 10 50
        exit 1
    fi
    
    # Show SD card info
    dialog --clear --title "SD Card Detected" \
        --msgbox "SD card found at:\n\n$SD_CARD" 10 50 || exit 1
    
    # Ask user preferences
    if ! ask_file_type; then
        exit 0
    fi
    
    # Ask for import directory
    local IMPORT_DIR
    IMPORT_DIR=$(ask_import_directory)
    if [ -z "$IMPORT_DIR" ]; then
        exit 0
    fi
    
    # Confirm before proceeding
    local confirm_msg="Ready to import $FILE_TYPES\n\n"
    confirm_msg+="Source: $SD_CARD\n"
    confirm_msg+="Destination: $IMPORT_DIR\n\n"
    confirm_msg+="Proceed with import?"
    
    if ! dialog --clear --title "Confirm Import" \
        --yesno "$confirm_msg" 12 60; then
        exit 0
    fi
    
    # Import files
    import_files "$SD_CARD" "$IMPORT_DIR"
    
    # Ask about unmounting
    if dialog --clear --title "Unmount SD Card" \
        --yesno "Import complete!\n\nUnmount SD card now?" 10 50; then
        unmount_card "$SD_CARD"
    fi
}

# Run main function
main "$@"
