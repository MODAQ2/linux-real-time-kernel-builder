# Build `RT_PREEMPT` kernel for Raspberry Pi

[![RPI RT Kernel build](https://github.com/ros-realtime/linux-real-time-kernel-builder/actions/workflows/rpi4-kernel-build.yml/badge.svg)](https://github.com/ros-realtime/linux-real-time-kernel-builder/actions/workflows/rpi4-kernel-build.yml)

## Introduction

This README describes necessary steps to build and install `RT_PREEMPT` Linux kernel for the Raspberry Pi board. RT Kernel is a part of the ROS2 real-time system setup.

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/ros-realtime/linux-real-time-kernel-builder
cd linux-real-time-kernel-builder
```

### 2. Download all required files locally

```bash
./download.sh
```

This script will:
- Find the latest raspi kernel release for your specified version
- Download the kernel buildinfo package (contains the kernel config)
- Download the appropriate RT patch
- Clone the kernel source from Launchpad

Optional: Specify kernel version and RT patch:
```bash
./download.sh 6.8.0 6.8.2-rt11
```

### 3. Build the Docker image

```bash
docker build -t rtwg-image .
```

### 4. Run the container and build the kernel

```bash
docker run -it rtwg-image bash
```

Inside the container:
```bash
cd /linux_build/linux-raspi
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-raspi -j $(nproc) bindeb-pkg
```

### 5. Copy the .deb packages

The build produces `.deb` packages in `/linux_build/`:
```bash
ls -la /linux_build/*.deb
```

Copy them to your host:
```bash
# From another terminal on the host
docker cp <container_id>:/linux_build/*.deb .
```

Or directly to your Raspberry Pi:
```bash
scp /linux_build/*.deb user@<raspberry_pi_ip>:/home/user/
```

## Files Structure

```
linux-real-time-kernel-builder/
├── download.sh          # Downloads kernel source, RT patch, and config locally
├── Dockerfile           # Docker build configuration
├── .config-fragment     # RT kernel configuration options
├── getpatch.sh          # Helper script to find matching RT patches
└── downloads/           # Created by download.sh
    ├── linux-raspi/     # Kernel source
    ├── patch-*.patch    # RT patch
    ├── config-*         # Kernel config
    ├── uname_r          # Kernel release version
    └── rt_patch         # RT patch version
```

## Kernel Configuration

The RT kernel is configured with options from `.config-fragment`:

- `CONFIG_PREEMPT_RT=y` - Full RT preemption
- `CONFIG_NO_HZ_FULL=y` - Full tickless operation
- `CONFIG_HZ_1000=y` - 1000Hz timer frequency
- `CONFIG_HIGH_RES_TIMERS=y` - High resolution timers
- `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` - Performance CPU governor

## Deploy New Kernel on Raspberry Pi

1. Copy the `.deb` packages to your Raspberry Pi

2. Install the packages:
```bash
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
```

3. Reboot:
```bash
sudo reboot
```

4. Verify the RT kernel is running:
```bash
uname -a
# Should show PREEMPT_RT in the output
```

## Troubleshooting

### Download script fails to clone kernel source

The Launchpad git server can be unreliable. The script will retry 3 times automatically. If it still fails:

1. Try again later
2. Use a VPN or different network
3. Clone manually:
```bash
git clone --filter=blob:none -b master --single-branch \
    https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble \
    downloads/linux-raspi
```

### Build fails with RT patch errors

The RT patch version must be close to the kernel version. If you see patch failures:

1. Check available RT patches at https://cdn.kernel.org/pub/linux/kernel/projects/rt/
2. Specify a compatible RT patch version:
```bash
./download.sh 6.8.0 6.8.2-rt11
```

### Docker build fails

Make sure you've run `./download.sh` first and all files exist in `downloads/`.

## Download Ready-to-Use RT Kernel

Pre-built RT kernel packages are available from GitHub Actions:

1. Go to the `Actions` tab
2. Find `Build stable` workflow
3. Download the artifacts from the latest successful run

## License

See [LICENSE](LICENSE) file.
