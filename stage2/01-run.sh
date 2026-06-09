#!/bin/bash -e
# Verbose mode – remove after debugging
set -x

echo "=== Starting custom configuration ==="

# ----------------------------------------------------------------------
# Disable WiFi, Bluetooth, onboard audio (write to boot config)
# ----------------------------------------------------------------------
on_chroot << EOF
echo "dtoverlay=disable-wifi" >> /boot/config.txt
echo "dtoverlay=disable-bt" >> /boot/config.txt
echo "dtparam=audio=off" >> /boot/config.txt
echo "blacklist snd_bcm2835" >> /etc/modprobe.d/audio-blacklist.conf
EOF

# ----------------------------------------------------------------------
# Virtual X11 display (1366x768)
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# Real-time priorities for JACK
# ----------------------------------------------------------------------
cat > /etc/security/limits.d/audio.conf << 'EOF'
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF

# Add pi user to audio group (works even if user created later by pi-gen)
# Use `on_chroot` for group modification inside target
on_chroot << EOF
usermod -a -G audio pi
EOF

# ----------------------------------------------------------------------
# VNC server for user pi
# ----------------------------------------------------------------------
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

# Systemd service for VNC (template)
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

# ----------------------------------------------------------------------
# noVNC for browser access
# ----------------------------------------------------------------------echo "Setting up noVNC..."
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

# ----------------------------------------------------------------------
# Install Jamulus (latest ARM64 .deb)
# ----------------------------------------------------------------------
on_chroot << EOF
# Download the latest Jamulus .deb for ARM
wget --retry-connrefused --waitretry=1 --timeout=20 --tries=5 \
  https://github.com/jamulussoftware/jamulus/releases/latest/download/jamulus_3.12.1_ubuntu_arm64.deb \
  -O /tmp/jamulus.deb
apt-get install -y /tmp/jamulus.deb
rm /tmp/jamulus.deb
EOF

# ----------------------------------------------------------------------
# Set USB audio as default (card 1 is typical for USB)
# ----------------------------------------------------------------------
cat > /etc/asound.conf << 'EOF'
defaults.ctl.card 1
defaults.pcm.card 1
EOF

# ----------------------------------------------------------------------
# Auto-login for pi user (LightDM)
# ----------------------------------------------------------------------
mkdir -p /etc/lightdm/lightdm.conf.d/
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf << 'EOF'
[Seat:*]
autologin-user=pi
autologin-user-timeout=0
EOF

# ----------------------------------------------------------------------
# Auto-start Jamulus in LXDE
# ----------------------------------------------------------------------
mkdir -p /home/pi/.config/lxsession/LXDE-pi
cat > /home/pi/.config/lxsession/LXDE-pi/autostart << 'EOF'
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
@/usr/bin/jamulus
EOF
chown -R pi:pi /home/pi/.config

# ----------------------------------------------------------------------
# Enable services
# ----------------------------------------------------------------------
on_chroot << EOF
systemctl enable vncserver@pi
systemctl enable novnc
systemctl enable lightdm
EOF

echo "=== Custom configuration finished successfully ==="