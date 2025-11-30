#!/bin/bash
# RampantVibe - Package Installation Script
# Install all required packages for the dotfiles

set -e  # Exit on error

echo "🚀 Installing RampantVibe packages..."

# Core packages
sudo pacman -Syu --needed \
    wallust yazi stow cava tlp delfin bitwarden qownnotes freetube \
    hyprpaper hypridle hyprlock \
    ttf-orbitron ttf-jetbrains-mono ttf-rajdhani ttf-exo ttf-audiowide oldschool-pc-fonts \
    network-manager-applet swww wpaperd waybar mako polkit-gnome alacritty \
    cliphist wl-clipboard playerctl gsettings-desktop-schemas \
    grim slurp swappy wofi xorg-xrdb pamixer brightnessctl nwg-launchers \
    thunar geany firedragon thunderbird github-desktop gparted inkscape \
    blender meld joplin-desktop snapper-tools galculator \
    libnotify jq mpv mediainfo fastfetch chafa python-numpy python-pyaudio \
    rmpc mpd fzf bat bat-extras perl-image-exiftool

# AUR packages (if yay is available)
if command -v yay &> /dev/null; then
    echo "📦 Installing AUR packages..."
    yay -S --needed proton-mail
else
    echo "⚠️  yay not found. Install proton-mail manually from AUR."
fi

echo "✅ Package installation complete!"
