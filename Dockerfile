# Dockerfile for RT Kernel Build
# 
# Prerequisites: Run ./download.sh first to download all required files locally
#
# Build: docker build -t rtwg-image .
# Run:   docker run -it rtwg-image bash
#
# Inside container:
#   cd /linux_build/linux-raspi
#   make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-raspi -j $(nproc) bindeb-pkg

FROM ubuntu:noble

USER root
ARG DEBIAN_FRONTEND=noninteractive

# Build arguments
ARG ARCH=arm64
ARG triple=aarch64-linux-gnu
ARG KERNEL_DIR=linux-raspi

# Setup timezone
RUN echo 'Etc/UTC' > /etc/timezone \
    && ln -s -f /usr/share/zoneinfo/Etc/UTC /etc/localtime \
    && apt-get update \
    && apt-get install -q -y tzdata apt-utils lsb-release software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Setup cross-compilation architecture
RUN apt-get update && apt-get install -q -y \
    gcc-${triple} \
    && dpkg --add-architecture ${ARCH} \
    && sed -i 's/deb h/deb [arch=amd64] h/g' /etc/apt/sources.list 2>/dev/null || true \
    && sed -i 's/deb h/deb [arch=amd64] h/g' /etc/apt/sources.list.d/* 2>/dev/null || true \
    && sed -i '/Components/a\Architectures: amd64' /etc/apt/sources.list.d/*.sources 2>/dev/null || true \
    && sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/*.sources 2>/dev/null || true \
    && echo "deb [arch=$ARCH] http://ports.ubuntu.com/ubuntu-ports/ $(lsb_release -s -c) main universe restricted" >> /etc/apt/sources.list.d/ubuntu-ports.list \
    && echo "deb-src http://archive.ubuntu.com/ubuntu $(lsb_release -s -c) main universe" >> /etc/apt/sources.list.d/ubuntu-ports.list \
    && echo "deb [arch=$ARCH] http://ports.ubuntu.com/ubuntu-ports $(lsb_release -s -c)-updates main universe restricted" >> /etc/apt/sources.list.d/ubuntu-ports.list \
    && rm -rf /var/lib/apt/lists/*

# Setup environment
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install kernel build dependencies
RUN apt-get update && apt-get build-dep -q -y linux \
    && apt-get install -q -y \
    libncurses-dev flex bison openssl libssl-dev dkms libelf-dev \
    libudev-dev libpci-dev libiberty-dev autoconf fakeroot \
    bc kmod cpio rsync \
    && rm -rf /var/lib/apt/lists/*

# Install utility packages
RUN apt-get update && apt-get install -q -y \
    sudo wget curl gzip git bash-completion time patch \
    && rm -rf /var/lib/apt/lists/*

# Remove default ubuntu user and create build user
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g 1000 user \
    && useradd -m -d /home/user -s /bin/bash -u 1000 -g 1000 user \
    && gpasswd -a user sudo \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && echo 'user:user' | chpasswd

# Create build directory
RUN mkdir -p /linux_build && chown user:user /linux_build

# Copy downloaded files (must run ./download.sh first!)
COPY --chown=user:user downloads/linux-raspi /linux_build/${KERNEL_DIR}
COPY --chown=user:user downloads/patch-*.patch /linux_build/
COPY --chown=user:user downloads/config-* /linux_build/
COPY --chown=user:user downloads/uname_r /home/user/
COPY --chown=user:user downloads/rt_patch /home/user/
COPY --chown=user:user .config-fragment /linux_build/

USER user
WORKDIR /linux_build/${KERNEL_DIR}

# Apply RT patch (allow skipping already applied hunks)
RUN cd /linux_build/${KERNEL_DIR} \
    && RT_PATCH=$(cat /home/user/rt_patch) \
    && echo "Applying RT patch: ${RT_PATCH}" \
    && patch -p1 --forward < /linux_build/patch-${RT_PATCH}.patch || true

# Setup kernel config with RT options
RUN UNAME_R=$(cat /home/user/uname_r) \
    && CONFIG_FILE=$(ls /linux_build/config-* 2>/dev/null | head -1) \
    && if [ -f "${CONFIG_FILE}" ]; then \
        cp "${CONFIG_FILE}" .config; \
    else \
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig; \
    fi \
    && ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- ./scripts/kconfig/merge_config.sh .config /linux_build/.config-fragment

# Clean and prepare for build
RUN make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Set default command
CMD ["/bin/bash"]
