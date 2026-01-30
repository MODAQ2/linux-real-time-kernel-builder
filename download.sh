#!/bin/bash
#
# Download script for RT kernel build requirements
# This script downloads all necessary files locally before Docker build
#
# Usage: ./download.sh [KERNEL_VERSION] [RT_PATCH]
# Example: ./download.sh 6.8.0 6.8.2-rt11
#

set -e

# Configuration - can be overridden by arguments
KERNEL_VERSION="${1:-6.8.0}"
RT_PATCH="${2:-}"
UBUNTU_VERSION="noble"
ARCH="arm64"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"

echo "=========================================="
echo "RT Kernel Download Script"
echo "=========================================="
echo "Kernel Version: ${KERNEL_VERSION}"
echo "Ubuntu Version: ${UBUNTU_VERSION}"
echo "Architecture: ${ARCH}"
echo "Download Directory: ${DOWNLOAD_DIR}"
echo "=========================================="

# Create download directory
mkdir -p "${DOWNLOAD_DIR}"
cd "${DOWNLOAD_DIR}"

# Extract major.minor for RT patch lookup
KERNEL_MAJOR_MINOR=$(echo "${KERNEL_VERSION}" | cut -d '.' -f 1-2)

echo ""
echo "[1/4] Finding latest raspi kernel release..."
# Find the latest buildinfo package to determine the kernel release
BUILDINFO_URL="http://ports.ubuntu.com/pool/main/l/linux-raspi/"
LATEST_BUILDINFO=$(curl -s "${BUILDINFO_URL}" | grep -oP "linux-buildinfo-${KERNEL_VERSION}-[0-9]+-raspi_[^\"]+_${ARCH}\.deb" | sort -V | tail -1)

if [ -z "${LATEST_BUILDINFO}" ]; then
    echo "ERROR: Could not find buildinfo package for kernel ${KERNEL_VERSION}"
    echo "Available versions:"
    curl -s "${BUILDINFO_URL}" | grep -oP "linux-buildinfo-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-raspi" | sort -V | uniq | tail -10
    exit 1
fi

# Extract UNAME_R from the buildinfo filename (e.g., 6.8.0-1047-raspi)
UNAME_R=$(echo "${LATEST_BUILDINFO}" | grep -oP "${KERNEL_VERSION}-[0-9]+-raspi")
echo "Found kernel release: ${UNAME_R}"
echo "${UNAME_R}" > "${DOWNLOAD_DIR}/uname_r"

# Download buildinfo package
echo ""
echo "[2/4] Downloading kernel buildinfo package..."
BUILDINFO_FILE="linux-buildinfo-${UNAME_R}.deb"
if [ ! -f "${BUILDINFO_FILE}" ]; then
    wget -q --show-progress "${BUILDINFO_URL}${LATEST_BUILDINFO}" -O "${BUILDINFO_FILE}"
else
    echo "Already downloaded: ${BUILDINFO_FILE}"
fi

# Extract config from buildinfo
echo "Extracting kernel config..."
mkdir -p buildinfo_extract
dpkg -x "${BUILDINFO_FILE}" buildinfo_extract/
CONFIG_FILE=$(find buildinfo_extract -name "config" -type f | head -1)
if [ -n "${CONFIG_FILE}" ]; then
    cp "${CONFIG_FILE}" "${DOWNLOAD_DIR}/config-${UNAME_R}"
    echo "Extracted config to: config-${UNAME_R}"
else
    echo "WARNING: Could not find config file in buildinfo package"
fi
rm -rf buildinfo_extract

# Find and download RT patch
echo ""
echo "[3/4] Finding RT patch..."
RT_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/projects/rt/${KERNEL_MAJOR_MINOR}"

if [ -z "${RT_PATCH}" ]; then
    # Find the best matching RT patch
    echo "Looking for RT patches at ${RT_BASE_URL}/older/..."
    PATCH_LIST=$(curl -s "${RT_BASE_URL}/older/" | grep -oP "patch-${KERNEL_MAJOR_MINOR}\.[0-9]+-rt[0-9]+\.patch\.gz" | sort -V | uniq)
    
    if [ -z "${PATCH_LIST}" ]; then
        # Try the main directory
        PATCH_LIST=$(curl -s "${RT_BASE_URL}/" | grep -oP "patch-${KERNEL_MAJOR_MINOR}\.[0-9]+-rt[0-9]+\.patch\.gz" | sort -V | uniq)
    fi
    
    if [ -z "${PATCH_LIST}" ]; then
        echo "ERROR: No RT patches found for kernel ${KERNEL_MAJOR_MINOR}"
        exit 1
    fi
    
    # Get the latest RT patch
    RT_PATCH_FILE=$(echo "${PATCH_LIST}" | tail -1)
    RT_PATCH=$(echo "${RT_PATCH_FILE}" | sed 's/patch-//' | sed 's/\.patch\.gz//')
    echo "Selected RT patch: ${RT_PATCH}"
else
    RT_PATCH_FILE="patch-${RT_PATCH}.patch.gz"
fi

echo "${RT_PATCH}" > "${DOWNLOAD_DIR}/rt_patch"

# Download RT patch
echo "Downloading RT patch..."
if [ ! -f "${RT_PATCH_FILE}" ]; then
    if ! wget -q --show-progress "${RT_BASE_URL}/older/${RT_PATCH_FILE}" -O "${RT_PATCH_FILE}" 2>/dev/null; then
        wget -q --show-progress "${RT_BASE_URL}/${RT_PATCH_FILE}" -O "${RT_PATCH_FILE}"
    fi
else
    echo "Already downloaded: ${RT_PATCH_FILE}"
fi

# Decompress if needed
if [ -f "${RT_PATCH_FILE}" ] && [ ! -f "patch-${RT_PATCH}.patch" ]; then
    echo "Decompressing RT patch..."
    gunzip -k "${RT_PATCH_FILE}"
fi

# Download kernel source tarball (much faster and more reliable than git clone)
echo ""
echo "[4/4] Downloading kernel source tarball..."
KERNEL_DIR="${DOWNLOAD_DIR}/linux-raspi"

# Get the RT patch kernel version (e.g., 6.8.2 from 6.8.2-rt11)
RT_KERNEL_VERSION=$(echo "${RT_PATCH}" | cut -d '-' -f 1)
KERNEL_MAJOR_MINOR_PATCH=${RT_KERNEL_VERSION}

# Download vanilla kernel that matches the RT patch
KERNEL_TARBALL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x"
TARBALL_FILE="linux-${RT_KERNEL_VERSION}.tar.xz"

if [ ! -f "${TARBALL_FILE}" ]; then
    echo "Downloading vanilla kernel ${RT_KERNEL_VERSION} to match RT patch..."
    wget -q --show-progress "${KERNEL_TARBALL_URL}/${TARBALL_FILE}" -O "${TARBALL_FILE}"
else
    echo "Already downloaded: ${TARBALL_FILE}"
fi

# Extract tarball
if [ ! -d "${KERNEL_DIR}" ]; then
    echo "Extracting kernel source..."
    mkdir -p "${KERNEL_DIR}"
    tar -xJf "${TARBALL_FILE}" --strip-components=1 -C "${KERNEL_DIR}"
    echo "Kernel source extracted to: ${KERNEL_DIR}"
else
    echo "Kernel source directory already exists: ${KERNEL_DIR}"
fi

cd "${DOWNLOAD_DIR}"

# Summary
echo ""
echo "=========================================="
echo "Download Complete!"
echo "=========================================="
echo "Kernel Release: ${UNAME_R}"
echo "RT Patch: ${RT_PATCH}"
echo "Kernel Source: ${TARBALL_FILE}"
echo ""
echo "Downloaded files in ${DOWNLOAD_DIR}:"
ls -la "${DOWNLOAD_DIR}"
echo ""
echo "Next steps:"
echo "  1. Review the downloads"
echo "  2. Run: docker build -t rtwg-image ."
echo "  3. Run: docker run -it rtwg-image bash"
echo "  4. Inside container: cd /linux_build/linux-raspi && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-raspi -j \$(nproc) bindeb-pkg"
echo "=========================================="
