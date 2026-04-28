# Use the official Ubuntu 20.04 image as the base
FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and upgrade the system packages
RUN apt update && \
    apt upgrade -y

# Install XFCE desktop environment and essential packages
RUN apt install -y \
    xfce4 \
    xfce4-goodies \
    tightvncserver \
    novnc \
    net-tools \
    nano \
    vim \
    neovim \
    curl \
    wget \
    firefox \
    git \
    python3 \
    python3-pip \
    lsb-release

# Set XFCE terminal as the default terminal emulator
RUN update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper

# Setup Chromium browser
RUN git clone https://github.com/scheib/chromium-latest-linux.git /chromium && \
    /chromium/update.sh

# ROS Noetic Desktop Full
RUN sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list' && \
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add - && \
    apt update && \
    apt install -y ros-noetic-desktop-full && \
    apt install -y python3-rosdep python3-rosinstall python3-rosinstall-generator python3-wstool build-essential && \
    rosdep init && \
    rosdep update

# Setup ROS environment
RUN echo "source /opt/ros/noetic/setup.bash" >> /root/.bashrc
ENV ROS_DISTRO=noetic

# Define environment variables for VNC and noVNC configuration
ARG USER=root
ENV USER=${USER}

ARG VNCPORT=5900
ENV VNCPORT=${VNCPORT}
EXPOSE ${VNCPORT}

ARG NOVNCPORT=9090
ENV NOVNCPORT=${NOVNCPORT}
EXPOSE ${NOVNCPORT}

ARG VNCPWD=changeme
ENV VNCPWD=${VNCPWD}

ARG VNCDISPLAY=1920x1080
ENV VNCDISPLAY=${VNCDISPLAY}

ARG VNCDEPTH=16
ENV VNCDEPTH=${VNCDEPTH}

# Setup VNC server configuration
RUN mkdir -p /root/.vnc/ && \
    echo ${VNCPWD} | vncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd && \
    echo "#!/bin/sh \n\
xrdb $HOME/.Xresources \n\
xsetroot -solid grey \n\
export XKL_XMODMAP_DISABLE=1 \n\
/etc/X11/Xsession \n\
startxfce4 & \n" > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

# Setup noVNC with SSL certificates
RUN openssl req -new -x509 -days 365 -nodes \
      -subj "/C=US/ST=IL/L=Springfield/O=OpenSource/CN=localhost" \
      -out /etc/ssl/certs/novnc_cert.pem -keyout /etc/ssl/private/novnc_key.pem && \
      cat /etc/ssl/certs/novnc_cert.pem /etc/ssl/private/novnc_key.pem > /etc/ssl/private/novnc_combined.pem && \
      chmod 600 /etc/ssl/private/novnc_combined.pem

# Define the entry point for the container
ENTRYPOINT ["/bin/bash", "-c", "\
  echo 'NoVNC Certificate Fingerprint:'; \
  openssl x509 -in /etc/ssl/certs/novnc_cert.pem -noout -fingerprint -sha256; \
  vncserver :0 -rfbport ${VNCPORT} -geometry $VNCDISPLAY -depth $VNCDEPTH -localhost; \
  /usr/share/novnc/utils/launch.sh --listen $NOVNCPORT --vnc localhost:$VNCPORT --cert /etc/ssl/private/novnc_combined.pem"]
