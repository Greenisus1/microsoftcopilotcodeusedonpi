#!/usr/bin/env bash

#------------------------------------------------------------------------------
#  "Copilot on Raspberry Pi" - Installation and Launch Script
#------------------------------------------------------------------------------
#  This script installs the necessary components (Box86/Box64 and Wine)
#  and configures a Raspberry Pi to run a Windows .exe application (Copilot).
#  It also handles secure storage of login credentials, Pi-Apps integration,
#  and optional remote desktop (VNC) setup for screen sharing.
#
#  Each major section of the script is explained with comments. The goal is to 
#  provide a user-friendly, interactive installation and usage experience.
#------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status (for safety).
set -e

# Enable error tracing (for debugging); comment this out in production.
#set -x

#---------------------#
#  UTILITY FUNCTIONS  #
#---------------------#

# Function: print_banner
# Description: Display an ASCII art banner for the application using figlet (if available) or fallback text.
print_banner() {
    echo ""
    if command -v figlet >/dev/null 2>&1; then
        figlet -c "Copilot on Pi"
    else
        echo "================================================="
        echo "     C O P I L O T   o n   R A S P B E R R Y   P I"
        echo "================================================="
    fi
    echo ""
}

# Function: spinner
# Description: Show a spinner animation while a background process ($1) is running.
spinner() {
    local pid=$1
    local delay=0.1
    local spin_chars='|/-\'
    tput civis  # hide cursor
    printf " "
    # Loop while process is running
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 $((${#spin_chars} - 1))); do
            printf "\b${spin_chars:$i:1}"
            sleep $delay
        done
    done
    printf "\b"  # backspace to erase spinner character
    tput cnorm  # show cursor
}

# Function: prompt_yes_no
# Description: Prompt the user with a yes/no question. Return 0 for yes, 1 for no.
prompt_yes_no() {
    local prompt="$1"
    local default="$2"   # "Y" or "N"
    local choice
    # Loop until we get a valid response
    while true; do
        read -rp "$prompt [Y/N] " choice
        choice=${choice:-$default}  # default if empty input
        case "$choice" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer Y or N." ;;
        esac
    done
}

# Function: error_exit
# Description: Print an error message and exit the script.
error_exit() {
    echo ""
    echo "❌ ERROR: $1"
    echo "Please see the above logs for details and consult the documentation for troubleshooting."
    exit 1
}

#-----------------------------#
#  SYSTEM & ARCH DETECTION    #
#-----------------------------#

print_banner  # Display the ASCII banner for the script

# Ensure this script is running on a Raspberry Pi (ARM architecture)
ARCH=$(uname -m)
if [[ "$ARCH" != "armv7l" && "$ARCH" != "aarch64" ]]; then
    error_exit "This script is designed for ARM-based Raspberry Pi devices. Detected architecture: $ARCH."
fi

# Identify 32-bit vs 64-bit OS
IS_64BIT=false
if [[ "$ARCH" == "aarch64" ]]; then
    IS_64BIT=true
fi

# Check Raspberry Pi model (for performance considerations)
PI_MODEL=$(tr -d '\0' </proc/device-tree/model)
if [[ "$PI_MODEL" =~ "Raspberry Pi 3" || "$PI_MODEL" =~ "Raspberry Pi 2" ]]; then
    echo "⚠️ Warning: $PI_MODEL detected. Performance may be limited for running x86 applications." >&2
fi

#-----------------------------#
#  DEPENDENCIES INSTALLATION  #
#-----------------------------#

echo "🔍 Checking and installing required dependencies..."

# List of common packages needed (git for cloning, ca-certificates for HTTPS, etc.)
COMMON_DEPS=(git wget curl ca-certificates dialog)
# Additional packages specifically for user experience and remote options
EXTRA_DEPS=(figlet x11vnc)

# Always update apt package lists first
sudo apt-get update -y

# Install dependencies (quietly, but show progress)
sudo apt-get install -y "${COMMON_DEPS[@]}" "${EXTRA_DEPS[@]}" > /dev/null 2>&1 & 
spinner $!  # Show spinner while installing

echo "✅ Dependencies installed."

#------------------------------#
#  BOX86 / BOX64 INSTALLATION  #
#------------------------------#

echo ""
echo "🔧 Setting up Box86/Box64 (x86 emulators for ARM)..."

# Box86 and Box64 allow x86 and x86_64 binaries to run on ARM-based devices like Raspberry Pi.
# They will be used to run Wine (and thus Windows apps) on the Raspberry Pi.
# If Box86/Box64 are already installed (perhaps via Pi-Apps or other), we skip installation.

# Check if Box86 and Box64 are already installed
BOX86_PATH="/usr/bin/box86"
BOX64_PATH="/usr/bin/box64"
if [[ -x "$BOX86_PATH" && -x "$BOX64_PATH" ]]; then
    echo "Box86 and Box64 are already installed on this system."
else
    echo "Installing Box86 and Box64..."
    # Box86/Box64 official installation script (from GitHub):
    BOX_INSTALLER_URL="https://raw.githubusercontent.com/ptitSeb/box86/master/install_box86_64.sh"
    # Download and run the installation script for Box86/Box64.
    wget -qO /tmp/install_box86_64.sh "$BOX_INSTALLER_URL" \
        || error_exit "Failed to download Box86/Box64 installer."
    chmod +x /tmp/install_box86_64.sh
    sudo /tmp/install_box86_64.sh || error_exit "Box86/Box64 installation failed."
fi

# Confirm installation by checking versions.
if box86 --version &>/dev/null && box64 --version &>/dev/null; then
    echo "✅ Box86/Box64 set up successfully."
else
    error_exit "Box86/Box64 did not install correctly."
fi

#-----------------------------------#
#  WINE SETUP (32-bit vs 64-bit)    #
#-----------------------------------#

echo ""
echo "🍷 Setting up Wine (Windows compatibility layer)..."

# Wine (for x86) is required to run Windows .exe applications on the Raspberry Pi through Box86/Box64.
# We will install the appropriate Wine version depending on the OS:
#  - On 32-bit Pi OS: use x86 (32-bit) Wine.
#  - On 64-bit Pi OS: use Wine with WoW64 (which includes both 64-bit and 32-bit support).

WINE_PREFIX="${HOME}/.wine-copilot"   # Use a dedicated Wine prefix for Copilot to avoid conflicts
export WINEPREFIX="$WINE_PREFIX"

if $IS_64BIT; then
    echo "Detected 64-bit OS. Installing Wine (x64 with WoW64 support)..."
    # Enable multiarch support for i386 on ARM64 by registering Box86 in binfmt_misc (if not already done).
    # This allows running i386 binaries (like 32-bit Wine components) under Box86 transparently.
    sudo update-binfmt --display | grep -q "box86" || {
        echo "Registering Box86 with binfmt_misc for i386 emulation..." 
        sudo /usr/bin/box86 --install || true  # This registers Box86 as handler for i386 ELF.
    }
    # Download Wine (x64) packages. We fetch both 64-bit and 32-bit Wine from WineHQ.
    # Using a recent Wine release for broad compatibility with apps.
    WINE_VERSION="8.0.1"  # using Wine stable 8.0.1 as an example
    CPU_ARCH="bullseye"   # default to bullseye; will adjust if running Bookworm
    if grep -q "bookworm" /etc/os-release; then
        CPU_ARCH="bookworm"
    fi
    echo "Downloading Wine $WINE_VERSION packages for $CPU_ARCH..."
    wget -q "https://dl.winehq.org/wine-builds/debian/dists/$CPU_ARCH/main/binary-amd64/wine-stable-amd64_${WINE_VERSION}~$CPU_ARCH-1_amd64.deb" -O /tmp/wine64.deb \
        || error_exit "Failed to download Wine 64-bit package."
    wget -q "https://dl.winehq.org/wine-builds/debian/dists/$CPU_ARCH/main/binary-i386/wine-stable-i386_${WINE_VERSION}~$CPU_ARCH-1_i386.deb" -O /tmp/wine32.deb \
        || error_exit "Failed to download Wine 32-bit package."
    # Extract the Wine packages (without trying to execute any post-install scripts):
    echo "Installing Wine (extracting .deb packages)..."
    dpkg-deb -x /tmp/wine64.deb /tmp/wine64
    dpkg-deb -x /tmp/wine32.deb /tmp/wine32
    # Merge the extracted files into a single Wine directory (in /opt for system-wide use).
    sudo mkdir -p /opt/wine-copilot
    sudo cp -r /tmp/wine64/* /opt/wine-copilot/
    sudo cp -r /tmp/wine32/* /opt/wine-copilot/
    # Create convenience symlinks for wine and winecfg
    sudo ln -sf /opt/wine-copilot/opt/wine-*/*/bin/wine /usr/local/bin/wine
    sudo ln -sf /opt/wine-copilot/opt/wine-*/*/bin/winecfg /usr/local/bin/winecfg
else
    echo "Detected 32-bit OS. Installing Wine (x86, 32-bit)..."
    # On 32-bit Raspberry Pi OS, we can run 32-bit x86 Wine directly under Box86.
    WINE_VERSION="8.0.1"  # stable Wine version
    CPU_ARCH="bullseye"
    if grep -q "bookworm" /etc/os-release; then
        CPU_ARCH="bookworm"
    fi
    echo "Downloading Wine $WINE_VERSION for $CPU_ARCH (x86)..."
    wget -q "https://dl.winehq.org/wine-builds/debian/dists/$CPU_ARCH/main/binary-i386/wine-stable-i386_${WINE_VERSION}~$CPU_ARCH-1_i386.deb" -O /tmp/wine32.deb \
        || error_exit "Failed to download Wine 32-bit package."
    # Extract the 32-bit Wine package
    echo "Installing Wine (extracting .deb package)..."
    dpkg-deb -x /tmp/wine32.deb /tmp/wine32
    sudo mkdir -p /opt/wine-copilot
    sudo cp -r /tmp/wine32/* /opt/wine-copilot/
    # Symlink the Wine binary for easy use
    sudo ln -sf /opt/wine-copilot/opt/wine-*/*/bin/wine /usr/local/bin/wine
    sudo ln -sf /opt/wine-copilot/opt/wine-*/*/bin/winecfg /usr/local/bin/winecfg
fi

# Verify Wine installation by checking the Wine version.
if ! wine --version &>/dev/null; then
    error_exit "Wine installation failed or wine binary not found."
fi
wine --version
echo "✅ Wine is set up successfully."

# Ensure the Wine prefix is initialized (creating a fresh Windows environment).
if [[ ! -d "$WINEPREFIX" ]]; then
    echo "Initializing Wine prefix at $WINEPREFIX (this may take a moment)..."
    winecfg -v win10 > /dev/null 2>&1 || true  # set Windows 10 version as default (non-interactively)
fi

#-----------------------------#
#  SECURE LOGIN DATA HANDLING #
#-----------------------------#

echo ""
echo "🔐 Configuring secure storage of login credentials..."

# Many Windows apps (including "Copilot") require user login. We will handle credentials securely.
# The script can save the login to a file encrypted with AES-256 to avoid re-entering each time.
# The user will need to provide a passphrase to decrypt the credentials when launching the app.

# Path to store encrypted credentials
CRED_FILE="${HOME}/.copilot_credentials.enc"

# Function: save_credentials
# Description: Prompt user for Copilot login and password, then store them encrypted.
save_credentials() {
    echo "Please enter your Copilot login credentials."
    read -rp "Username: " COPILOT_USER
    # Use `read -s` to silently accept password input (no echo on terminal)
    read -srp "Password: " COPILOT_PASS
    echo ""
    # Prompt for an encryption key to secure the credentials file
    echo "Create a passphrase to encrypt your credentials (do NOT forget this passphrase)."
    read -srp "Encryption Passphrase: " ENC_PASS1
    echo ""
    read -srp "Confirm Passphrase: " ENC_PASS2
    echo ""
    if [[ "$ENC_PASS1" != "$ENC_PASS2" || -z "$ENC_PASS1" ]]; then
        echo "❌ Passphrases did not match or were empty. Credentials not saved."
        return 1
    fi
    # Encrypt and save credentials (username:password) using OpenSSL AES-256-CBC.
    local plaintext="${COPILOT_USER}:${COPILOT_PASS}"
    echo -n "$plaintext" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$ENC_PASS1" -out "$CRED_FILE" \
        || { echo "Failed to encrypt credentials."; return 1; }
    chmod 600 "$CRED_FILE"
    unset COPILOT_PASS plaintext ENC_PASS1 ENC_PASS2  # clear sensitive data from memory
    echo "✅ Credentials saved securely to $CRED_FILE."
    echo "NOTE: You will need to enter your encryption passphrase to decrypt credentials on each run."
    return 0
}

# Check if credentials file already exists
if [[ -f "$CRED_FILE" ]]; then
    echo "Encrypted credentials file found."
    if prompt_yes_no "Do you want to use the saved credentials?" "Y"; then
        # Ask for decryption passphrase
        read -srp "Enter encryption passphrase to unlock credentials: " ENC_PASS
        echo ""
        # Decrypt credentials
        CREDENTIALS=$(openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:"$ENC_PASS" -in "$CRED_FILE" 2>/dev/null) || {
            echo "❌ Incorrect passphrase or decryption failed."
            CREDENTIALS=""
        }
        unset ENC_PASS
        if [[ -z "$CREDENTIALS" ]]; then
            if ! prompt_yes_no "Failed to decrypt. Re-enter credentials and update the saved file?" "Y"; then
                error_exit "Cannot proceed without valid credentials."
            fi
            # Remove invalid file and prompt to save new credentials
            rm -f "$CRED_FILE"
            save_credentials || true
        else
            # Split the "username:password" format into two variables
            COPILOT_USER="${CREDENTIALS%%:*}"
            COPILOT_PASS="${CREDENTIALS#*:}"
            echo "✅ Credentials decrypted successfully."
        fi
    else
        # User chose not to use saved credentials (maybe to update them)
        rm -f "$CRED_FILE"
        save_credentials || true
    fi
else
    # No credentials saved yet, ask user if they want to save for future
    if prompt_yes_no "Would you like to save your Copilot login for future use?" "Y"; then
        save_credentials || true
    else
        # If not saving, just prompt for credentials to use this session (will not be saved)
        read -rp "Username: " COPILOT_USER
        read -srp "Password: " COPILOT_PASS
        echo ""
    fi
fi

# At this point, COPILOT_USER and COPILOT_PASS should be set (either from decrypted file or input).
# Note: COPILOT_PASS may be empty if using saved creds that failed; we handle that above by prompting if decryption failed.

#-----------------------------#
#   COPILOT APP INSTALLATION  #
#-----------------------------#

echo ""
echo "📦 Preparing Copilot application..."

# The script expects the Copilot .exe installer or program to be available.
# This could be pre-downloaded by the user or retrieved via URL if known.
# We will prompt the user for the path to the Copilot .exe file if not provided as an argument.

COPILOT_EXE="$1"
if [[ -z "$COPILOT_EXE" ]]; then
    read -rp "Enter the path or URL of the Copilot .exe: " COPILOT_EXE
fi

# If a URL is provided instead of a local file path, download it.
if [[ "$COPILOT_EXE" =~ ^https?:// ]]; then
    echo "Downloading Copilot from $COPILOT_EXE..."
    wget -O "/tmp/Copilot.exe" "$COPILOT_EXE" \
        || error_exit "Failed to download Copilot .exe from provided URL."
    COPILOT_EXE="/tmp/Copilot.exe"
fi

# Verify the .exe file exists
if [[ ! -f "$COPILOT_EXE" ]]; then
    error_exit "Could not find Copilot .exe at '$COPILOT_EXE'. Please provide a valid path."
fi

# Determine if the .exe is 32-bit or 64-bit (PE32 for 32-bit, PE32+ for 64-bit).
EXE_TYPE=$(file -b "$COPILOT_EXE" | grep -o "PE32+*")
if [[ "$EXE_TYPE" == "PE32+" ]]; then
    APP_BITS=64
else
    APP_BITS=32
fi
echo "Copilot .exe appears to be a $APP_BITS-bit Windows application."

# Setup Wine prefix architecture accordingly
if [[ $APP_BITS -eq 32 && $IS_64BIT == true ]]; then
    # For a 32-bit app on 64-bit OS, ensure WINEPREFIX is set to 32-bit mode for best compatibility.
    export WINEARCH=win32
fi

# If the Copilot app needs to be installed (like a setup program), run the installer first.
echo "Launching Copilot installer/application via Wine..."
wine "$COPILOT_EXE" &> wine_log.txt &  # Run in background and log output to file for debugging
WINE_PID=$!
spinner $WINE_PID  # Show spinner while the app is running or installing
wait $WINE_PID    # Wait for the Wine process to finish
WINE_EXIT_CODE=$?
if [[ $WINE_EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "⚠️ Copilot process exited with code $WINE_EXIT_CODE. Check wine_log.txt for details if the app did not run correctly."
fi

# If this was an installer, after it finishes, we might have the actual application installed.
# For example, Copilot might install to C:\\Program Files\\Copilot.
# The user might need to run the actual app executable. We can attempt to auto-detect it:
COPILOT_INSTALL_DIR=$(find "${WINEPREFIX}/drive_c" -maxdepth 2 -type d -name "*Copilot*" 2>/dev/null | head -n1)
COPILOT_MAIN_EXE=""
if [[ -n "$COPILOT_INSTALL_DIR" ]]; then
    COPILOT_MAIN_EXE=$(find "$COPILOT_INSTALL_DIR" -type f -iname "copilot*.exe" 2>/dev/null | head -n1)
fi

# Ask user if they want to run the app immediately (if not an installer or after install)
if [[ -n "$COPILOT_MAIN_EXE" ]]; then
    echo "Copilot appears to be installed at: $COPILOT_INSTALL_DIR"
    if prompt_yes_no "Do you want to launch Copilot now?" "Y"; then
        echo "Launching Copilot..."
        wine "$COPILOT_MAIN_EXE" &> wine_log.txt &
        COPILOT_PID=$!
    fi
else
    # If we didn't find an installed directory, we assume the provided .exe was the app itself and is already running (or finished).
    COPILOT_PID=$WINE_PID
fi

# Optionally, handle login within the app if possible.
# (Note: If Copilot has command-line options to pass credentials, we could use them here.)
# As a placeholder, we remind user to log in, or if the app auto-launched, maybe the credentials are pre-filled if saved.
echo ""
echo "🚀 Copilot should now be running. If prompted, please log in with your credentials."
echo "(If credentials were saved, the app may have auto-filled them or kept you logged in from a previous session.)"
echo ""

#---------------------------------#
#  REMOTE ACCESS (SCREEN SHARE)   #
#---------------------------------#

echo "🖥️ Setting up optional remote desktop access..."

# The script can enable VNC-based screen sharing to view/control Copilot remotely.
# Raspberry Pi OS has a built-in VNC server (RealVNC) which can be enabled via raspi-config.
# Here, we offer to either enable the built-in VNC or use x11vnc for a user-session share.

REMOTE_OPTION=""
if prompt_yes_no "Do you want to enable remote desktop (VNC) access to the Copilot UI?" "N"; then
    echo "Choose remote access method:"
    echo "1) Use Raspberry Pi's built-in RealVNC server (recommended for full desktop sharing)."
    echo "2) Use a user-level x11vnc server (share the current session only)."
    read -rp "Enter choice [1 or 2]: " REMOTE_OPTION
    if [[ "$REMOTE_OPTION" == "1" ]]; then
        echo "Enabling built-in RealVNC server..."
        # Use raspi-config non-interactively to enable VNC (RealVNC).
        sudo raspi-config nonint do_vnc 0 || true
        echo "RealVNC server should be enabled. You may need to reboot for it to start."
        echo "👉 To use RealVNC, ensure you have a VNC viewer on your PC. Connect to ${HOSTNAME}.local:5900 (or the Pi's IP)."
    elif [[ "$REMOTE_OPTION" == "2" ]]; then
        echo "Starting x11vnc server for the current session..."
        x11vnc -forever -usepw -shared -bg -o "${HOME}/.x11vnc.log" \
            || error_exit "Failed to start x11vnc. Make sure an X session is running."
        echo "👉 x11vnc is running. You can connect with a VNC viewer to ${HOSTNAME}.local:5900 (password is required)."
        echo "To set/change the VNC password, run: x11vnc -storepasswd"
    else
        echo "No valid choice entered. Skipping remote access setup."
    fi
else
    echo "Remote desktop access not enabled."
fi

#-----------------------------#
#  PI-APPS INTEGRATION        #
#-----------------------------#

echo ""
echo "📂 Integrating with Pi-Apps (if available)..."

# Pi-Apps is a popular app store for Raspberry Pi. We can add Copilot to Pi-Apps for easy future access.
# This typically involves creating an install script and metadata so Pi-Apps recognizes it.
# Here, we'll simply add a launcher and notify the user for manual Pi-Apps integration if desired.

# Create a desktop entry for Copilot in the Raspberry Pi menu (for GUI launch).
DESKTOP_FILE="$HOME/Desktop/Copilot.desktop"
echo "Creating desktop shortcut at $DESKTOP_FILE"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Copilot (Wine)
Comment=Run Copilot (Windows app via Wine)
Exec=wine "${COPILOT_MAIN_EXE:-$COPILOT_EXE}"
Type=Application
Icon=application-x-executable
Categories=Utility;
EOF
chmod +x "$DESKTOP_FILE"

# If Pi-Apps is installed, suggest adding to Pi-Apps.
if [[ -d "$HOME/pi-apps/apps" ]]; then
    echo "Pi-Apps detected. You can integrate this script into Pi-Apps by creating a directory under ~/pi-apps/apps."
    echo "👉 For Pi-Apps integration, copy this script into ~/pi-apps/apps/Copilot/install and create an entry as per Pi-Apps guidelines."
else
    echo "Pi-Apps not found. If you plan to distribute this via Pi-Apps, follow their app submission guidelines."
fi

#-----------------------------#
#  CLEANUP AND FINAL NOTES    #
#-----------------------------#

echo ""
echo "🎉 All done! Copilot setup is complete."

if [[ "$REMOTE_OPTION" == "1" ]]; then
    echo "💡 Please reboot your Raspberry Pi for VNC (RealVNC) settings to take effect, then you can connect remotely to use Copilot."
elif [[ "$REMOTE_OPTION" == "2" ]]; then
    echo "💡 The x11vnc server is still running in the background. It will terminate when you log out or shut down."
fi

echo "✅ You can launch Copilot in the future via the desktop shortcut or by running:"
echo "   wine ${COPILOT_MAIN_EXE:-$COPILOT_EXE}"
echo ""
echo "For troubleshooting:"
echo " - See the Wine log output in wine_log.txt if Copilot didn't run correctly."
echo " - Ensure Box86/Box64 are updated to the latest version for best compatibility."
echo " - Check Raspberry Pi forums and the Copilot documentation for any Pi-specific tweaks."
echo ""
echo "👍 Thank you for using the Copilot on Pi installer! Enjoy your application."
