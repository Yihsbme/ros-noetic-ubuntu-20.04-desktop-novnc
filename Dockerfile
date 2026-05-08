FROM ubuntu:20.04

LABEL maintainer="docker-ubuntu-ros-novnc"

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=ubuntu \
    PASSWORD=ubuntu \
    UID=1000 \
    GID=1000

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all
ENV HTTPS_CERT=/etc/ssl/certs/ssl-cert-snakeoil.pem
ENV HTTPS_CERT_KEY=/etc/ssl/private/ssl-cert-snakeoil.key
ENV VGL_DISPLAY=egl
ENV VNC_RESOLUTION=1920x1080
ENV VNC_THREADS=2

# REMOVED: 错误的环境变量 (指向宿主机 D-Bus)
# ENV DBUS_SYSTEM_BUS_ADDRESS=unix:path=/host/run/dbus/system_bus_socket

#======================================
# 1. Install basic tools
#======================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo vim gedit locales gnupg2 wget curl zip lsb-release bash-completion \
        net-tools iputils-ping mesa-utils software-properties-common build-essential \
        python3 python3-pip python3-numpy \
        openssh-server openssl git git-lfs tmux \
        libxau6 libxdmcp6 libxcb1 libxext6 libx11-6 \
        libglvnd0 libgl1 libglx0 libegl1 libgles2 \
        libglvnd-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev \
        vulkan-tools && \
    rm -rf /var/lib/apt/lists/*

# Configure OpenGL
RUN mkdir -p /usr/share/glvnd/egl_vendor.d/ && \
    echo '{\n\
"file_format_version" : "1.0.0",\n\
"ICD": {\n\
    "library_path": "libEGL_nvidia.so.0"\n\
}\n\
}' > /usr/share/glvnd/egl_vendor.d/10_nvidia.json

# Configure Vulkan
RUN VULKAN_API_VERSION=$(dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+' | grep -oP '[0-9]+(\.[0-9]+)(\.[0-9]+)') && \
    mkdir -p /etc/vulkan/icd.d/ && \
    echo "{\n\
\"file_format_version\" : \"1.0.0\",\n\
\"ICD\": {\n\
    \"library_path\": \"libGLX_nvidia.so.0\",\n\
    \"api_version\" : \"${VULKAN_API_VERSION}\"\n\
}\n\
}" > /etc/vulkan/icd.d/nvidia_icd.json

#======================================
# 2. Install desktop environment & D-Bus & Rime Input Method
#======================================
RUN apt-get update && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    mkdir -p /etc/apt/preferences.d && \
    echo "Package: firefox*\n\
Pin: release o=LP-PPA-mozillateam\n\
Pin-Priority: 1001" > /etc/apt/preferences.d/mozilla-firefox && \
    apt-get install -y xfce4 terminator fonts-wqy-zenhei pulseaudio ffmpeg firefox \
                       dbus dbus-x11 fcitx fcitx-config-gtk && \
    # 安装 Rime 输入法引擎
    apt-get install -y fcitx-rime && \
    # 可选：安装中文字体增强 (已有 wqy-zenhei，再装一个更全的)
    apt-get install -y fonts-noto-cjk && \
    rm -rf /var/lib/apt/lists/*

# 确保 D-Bus 运行时目录存在
RUN mkdir -p /var/run/dbus && \
    chmod 755 /var/run/dbus

# 设置输入法环境变量 (将在启动脚本中再次导出)
ENV GTK_IM_MODULE=fcitx \
    QT_IM_MODULE=fcitx \
    XMODIFIERS=@im=fcitx

#======================================
# 3. Install ROS Noetic Desktop
#======================================
RUN apt-get update && \
    apt-get install -y curl gnupg2 lsb-release software-properties-common && \
    echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list && \
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y ros-noetic-desktop-full && \
    apt-get install -y python3-rosdep python3-rosinstall python3-rosinstall-generator python3-wstool build-essential python3-catkin-tools && \
    (rosdep init || true) && \
    rm -rf /var/lib/apt/lists/*

# Setup ROS environment
RUN echo "source /opt/ros/noetic/setup.bash" >> /etc/bash.bashrc

#======================================
# 4. Install noVNC (TurboVNC + noVNC)
#======================================
ENV NOVNC_VERSION=1.6.0
RUN wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg && \
    wget -O /etc/apt/sources.list.d/TurboVNC.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list && \
    apt-get update && \
    apt-get install -y turbovnc && \
    rm /etc/apt/sources.list.d/TurboVNC.list && \
    curl -fsSL "https://github.com/novnc/noVNC/archive/v${NOVNC_VERSION}.tar.gz" | tar -xzf - -C /opt && \
    mv -f "/opt/noVNC-${NOVNC_VERSION}" /opt/noVNC && \
    ln -snf /opt/noVNC/vnc.html /opt/noVNC/index.html && \
    git clone "https://github.com/novnc/websockify.git" /opt/noVNC/utils/websockify && \
    # MODIFY: 修改 xstartup，使用 dbus-launch 启动 Xfce
    echo '#! /bin/sh\n\
xset s off\n\
export GTK_IM_MODULE=fcitx\n\
export QT_IM_MODULE=fcitx\n\
export XMODIFIERS=@im=fcitx\n\
# 启动输入法 (Rime 依赖 fcitx)\n\
fcitx -r &\n\
# 通过 dbus-launch 启动桌面会话\n\
dbus-launch --exit-with-session /usr/bin/startxfce4' > /opt/TurboVNC/bin/xstartup.turbovnc && \
    rm -rf /var/lib/apt/lists/*

#======================================
# 5. Configure SSH
#======================================
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

#======================================
# 6. Create startup scripts
#======================================
RUN mkdir -p /docker_config

# Create start_novnc.sh
# MODIFY: 在启动 VNC 之前先启动系统 D-Bus 守护进程（提供系统总线）
# MODIFY: 确保用户环境变量包含输入法相关变量
RUN echo '#!/bin/sh\n\
VNC_RESOLUTION=${VNC_RESOLUTION:-1920x1080}\n\
\n\
# 启动系统 D-Bus 守护进程（如果未运行）\n\
if [ ! -e /var/run/dbus/system_bus_socket ]; then\n\
    dbus-daemon --system --fork\n\
fi\n\
\n\
# 确保 .vnc 目录存在并设置权限\n\
if [ ! -d "/home/$USER/.vnc" ]; then\n\
    mkdir -p /home/$USER/.vnc\n\
    chown $UID:$GID /home/$USER/.vnc\n\
    chmod 700 /home/$USER/.vnc\n\
fi\n\
\n\
# 设置 TurboVNC 密码\n\
if [ ! -f "/home/$USER/.vnc/passwd" ]; then\n\
    su $USER -c "echo -e \""$PASSWORD"\n"$PASSWORD"\ny\n\" | /opt/TurboVNC/bin/vncpasswd"\n\
fi\n\
\n\
# 清理锁文件\n\
rm -rf /tmp/.X1000-lock /tmp/.X11-unix/X1000\n\
\n\
# 准备用户环境变量文件（供 dbus-launch 继承）\n\
echo "export GTK_IM_MODULE=fcitx" >> /home/$USER/.bashrc\n\
echo "export QT_IM_MODULE=fcitx" >> /home/$USER/.bashrc\n\
echo "export XMODIFIERS=@im=fcitx" >> /home/$USER/.bashrc\n\
\n\
echo "Starting TurboVNC with resolution: $VNC_RESOLUTION"\n\
su $USER -c "/opt/TurboVNC/bin/vncserver :1000 -rfbport 5900 -geometry $VNC_RESOLUTION"\n\
\n\
if [ ! -z ${DISABLE_HTTPS+x} ]; then\n\
    su $USER -c "/opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 4000 --heartbeat 10 &"\n\
else\n\
    su $USER -c "/opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --ssl-only --cert $HTTPS_CERT --key $HTTPS_CERT_KEY --listen 4000 --heartbeat 10 &"\n\
fi\n\
\n\
tail -f /home/$USER/.vnc/*.log' > /docker_config/start_novnc.sh && \
    chmod +x /docker_config/start_novnc.sh

#======================================
# 7. Create entrypoint script (unchanged except small addition)
#======================================
# MODIFY: 确保 /run/user/$UID 存在且权限正确 (D-Bus 需要)
RUN echo '#!/bin/sh\n\
## Initialize environment\n\
if [ ! -f "/docker_config/init_flag" ]; then\n\
    update-alternatives --install /usr/bin/python python /usr/bin/python3 2\n\
    export PATH=/usr/NX/scripts/vgl:$PATH\n\
    env | grep -Ev "CMD=|PWD=|SHLVL=|_=|DEBIAN_FRONTEND=|USER=|HOME=|UID=|GID=|PASSWORD=" > /etc/environment\n\
    groupadd -g $GID $USER\n\
    useradd --create-home --no-log-init -u $UID -g $GID $USER\n\
    usermod -aG sudo $USER\n\
    usermod -aG ssl-cert $USER\n\
    echo "root:$PASSWORD" | chpasswd\n\
    echo "$USER:$PASSWORD" | chpasswd\n\
    chsh -s /bin/bash $USER\n\
    mkdir -p /run/user/$UID\n\
    chown $GID:$UID /run/user/$UID\n\
    # 确保 DBus 运行时目录权限\n\
    chown -R $UID:$GID /var/run/dbus 2>/dev/null || true\n\
    # Create .vnc directory with correct permissions\n\
    mkdir -p /home/$USER/.vnc\n\
    chown $UID:$GID /home/$USER/.vnc\n\
    chmod 700 /home/$USER/.vnc\n\
    # Fix home directory permissions for XFCE\n\
    chown -R $UID:$GID /home/$USER\n\
    chmod 755 /home/$USER\n\
    if [ -f "/docker_config/env_init.sh" ]; then\n\
        bash /docker_config/env_init.sh\n\
    fi\n\
    if [ -f "/docker_config/custom_env_init.sh" ]; then\n\
        bash /docker_config/custom_env_init.sh\n\
    fi\n\
    echo "ok" > /docker_config/init_flag\n\
fi\n\
## Startup\n\
if [ -f "/docker_config/custom_startup.sh" ]; then\n\
    bash /docker_config/custom_startup.sh\n\
fi\n\
/usr/sbin/sshd\n\
echo "start novnc"\n\
bash /docker_config/start_novnc.sh' > /docker_config/entrypoint.sh && \
    chmod +x /docker_config/entrypoint.sh

#======================================
# 8. Expose ports and set entrypoint
#======================================
EXPOSE 22 4000

ENTRYPOINT ["/docker_config/entrypoint.sh"]