#!/bin/bash -e

# # --- 1. System Update and Base Setup ---
# echo "Running system update and installing base packages..."
# on_chroot << EOF
# apt-get update
# apt-get -y dist-upgrade
# apt-get install -y \
#     xserver-xorg-video-dummy \
#     lxde-core \
#     lightdm \
#     tigervnc-standalone-server \
#     novnc \
#     websockify \
#     jackd2 \
#     qjackctl \
#     alsa-utils \
#     alsa-tools \
#     build-essential \
#     qt5-qmake \
#     qtdeclarative5-dev \
#     qt5-default \
#     git \
#     wget \
#     curl \
#     unzip \
#     tmux \
#     htop \
#     vim \
#     mtr-tiny
# EOF

# Auto-login for pi user
mkdir -p /etc/lightdm/lightdm.conf.d/
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf << 'EOF'
[Seat:*]
autologin-user=pi
autologin-user-timeout=0
EOF

# Auto-start Jamulus after desktop loads
mkdir -p /home/pi/.config/lxsession/LXDE-pi
cat > /home/pi/.config/lxsession/LXDE-pi/autostart << 'EOF'
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
@/usr/bin/jamulus
EOF
chown -R pi:pi /home/pi/.config

# --- 2. Disable WiFi and Bluetooth ---
echo "Disabling WiFi and Bluetooth..."
echo "dtoverlay=disable-wifi" >> /boot/config.txt
echo "dtoverlay=disable-bt" >> /boot/config.txt

# --- 3. Disable Onboard Audio ---
echo "Disabling onboard audio..."
echo "dtparam=audio=off" >> /boot/config.txt
echo "blacklist snd_bcm2835" >> /etc/modprobe.d/audio-blacklist.conf

# --- 4. Configure Virtual X11 Display (for headless operation) ---
echo "Configuring virtual X11 display..."
mkdir -p /etc/X11/xorg.conf.d/
cat > /etc/X11/xorg.conf.d/99-fake-display.conf << 'EOF'
Section "Device"
    Identifier  "DummyDevice"
    Driver      "dummy"
    VideoRam    256000
EndSection

Section "Monitor"
    Identifier  "DummyMonitor"
    HorizSync   28.0-80.0
    VertRefresh 60.0-80.0
    Modeline "1366x768" 85.50 1366 1432 1568 1776 768 771 777 798 +hsync +vsync
EndSection

Section "Screen"
    Identifier  "DummyScreen"
    Device      "DummyDevice"
    Monitor     "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1366x768"
    EndSubSection
EndSection
EOF

# --- 5. Set up Real-time Priorities for JACK ---
echo "Setting up real-time priorities for JACK..."
cat > /etc/security/limits.d/audio.conf << 'EOF'
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF

# Add the 'pi' user to the 'audio' group to apply permissions
usermod -a -G audio pi

# --- 6. Configure VNC Server for User 'pi' ---
echo "Configuring VNC server for user 'pi'..."
mkdir -p /home/pi/.vnc
cat > /home/pi/.vnc/config << 'EOF'
session=lxde
geometry=1366x768
localhost
alwaysshared
EOF

cat > /home/pi/.vnc/xstartup << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
/etc/X11/xinit/xinitrc
startlxde &
EOF

chmod +x /home/pi/.vnc/xstartup
chown -R pi:pi /home/pi/.vnc

# Create a systemd service for VNC
cat > /etc/systemd/system/vncserver@.service << 'EOF'
[Unit]
Description=TigerVNC server for user %i
After=syslog.target network.target

[Service]
Type=forking
User=%i
ExecStartPre=/bin/sh -c 'vncserver -kill :1 > /dev/null 2>&1 || :'
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1366x768 :1
ExecStop=/usr/bin/vncserver -kill :1
PIDFile=/home/%i/.vnc/%%H-%i.pid

[Install]
WantedBy=multi-user.target
EOF

# --- 7. Set up noVNC for Browser-based Access ---
echo "Setting up noVNC..."
mkdir -p /home/pi/novnc/utils/websockify
cat > /etc/systemd/system/novnc.service << 'EOF'
[Unit]
Description=noVNC service
After=network.target [email protected]

[Service]
Type=simple
User=pi
ExecStart=/usr/share/novnc/utils/novnc_proxy --vnc localhost:5901 --listen 6080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --- 8. Install and Configure Jamulus ---
echo "Installing Jamulus..."
on_chroot << EOF
# Download the latest Jamulus .deb for ARM
wget https://github.com/jamulussoftware/jamulus/releases/latest/download/jamulus_3.12.1_ubuntu_arm64.deb -O /tmp/jamulus.deb
apt-get install -y /tmp/jamulus.deb
rm /tmp/jamulus.deb
EOF

# --- 9. Set USB Audio Interface as Default ---
echo "Configuring USB audio as default..."
cat > /etc/asound.conf << 'EOF'
defaults.ctl.card 1
defaults.pcm.card 1
EOF

# --- 10. Enable Services and Clean Up ---
echo "Enabling services and cleaning up..."
on_chroot << EOF
systemctl enable vncserver@pi
systemctl enable novnc
systemctl enable lightdm
EOF

echo "Custom image build script finished."