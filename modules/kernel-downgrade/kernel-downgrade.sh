#!/usr/bin/bash

set -eoux pipefail

# Get module configuration JSON
MODULE_CONFIG_JSON="$1"

# Parse configuration options using jq
TARGET_KERNEL_VERSION=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.target_kernel_version // "6.14"')
REMOVE_NEWER_KERNELS=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.remove_newer_kernels // true')
EXCLUDE_PACKAGES=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.exclude_packages // "kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-devel kernel-headers"')

echo "=== Kernel Downgrade Module ==="
echo "Target Kernel Version: $TARGET_KERNEL_VERSION"
echo "Remove Newer Kernels: $REMOVE_NEWER_KERNELS"
echo "Exclude Packages: $EXCLUDE_PACKAGES"

# Function to compare version strings
version_compare() {
    printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1
}

# Get currently installed kernel packages
echo "Checking currently installed kernels..."
CURRENT_KERNELS=$(rpm -qa | grep "^kernel-" | grep -v "kernel-tools" | grep -v "kernel-firmware" | sort)
echo "Current kernel packages:"
echo "$CURRENT_KERNELS"

# First, remove existing kernel version locks that might prevent downgrade
echo "Removing existing kernel version locks..."
dnf5 versionlock clear 2>/dev/null || echo "No version locks to clear"
dnf5 versionlock delete 'kernel*' 2>/dev/null || echo "No kernel version locks to remove"

# Also try to remove any versionlock files directly
rm -f /etc/dnf/versionlock.list 2>/dev/null || true
rm -f /etc/yum/versionlock.list 2>/dev/null || true

# Clear any exclude configurations that might block kernel installation
echo "Temporarily clearing DNF excludes..."
mkdir -p /etc/dnf
if [ -f /etc/dnf/dnf.conf ]; then
    cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.backup
    sed -i '/^exclude=/d' /etc/dnf/dnf.conf
fi

# Enable the updates-archive repository specifically for older kernels
echo "Enabling updates-archive repository for kernel access..."
dnf5 config-manager --set-enabled updates-archive 2>/dev/null || echo "updates-archive repo may not exist"

# Clean DNF cache to ensure fresh package metadata
echo "Cleaning DNF cache..."
dnf5 clean all

# Remove newer kernels first to avoid conflicts
if [ "$REMOVE_NEWER_KERNELS" = "true" ]; then
    echo "Removing newer kernel packages to avoid conflicts..."
    
    # Remove newer kernel packages forcefully
    echo "Removing kernel packages newer than $TARGET_KERNEL_VERSION..."
    
    # List all installed kernel packages and remove those newer than target
    KERNEL_PACKAGES=$(rpm -qa | grep "^kernel-" | grep -v "kernel-tools" | grep -v "kernel-firmware")
    
    for pkg in $KERNEL_PACKAGES; do
        PKG_VERSION=$(echo "$pkg" | sed 's/.*-\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/')
        if [ -n "$PKG_VERSION" ]; then
            OLDER_VERSION=$(version_compare "$TARGET_KERNEL_VERSION" "$PKG_VERSION")
            if [ "$OLDER_VERSION" = "$TARGET_KERNEL_VERSION" ] && [ "$PKG_VERSION" != "$TARGET_KERNEL_VERSION" ]; then
                echo "Removing newer kernel package: $pkg"
                rpm -e --nodeps "$pkg" 2>/dev/null || echo "Failed to remove $pkg, continuing..."
            fi
        fi
    done
fi

# Now try to install kernel 6.14.11 specifically
echo "Installing kernel 6.14.11..."

# First, try to find available kernel versions
echo "Available kernel packages:"
dnf5 list available "kernel-core*" --repo updates-archive 2>/dev/null || dnf5 list available "kernel-core*" || true

# Install kernel 6.14.11 specifically
echo "Installing kernel version: 6.14.11"

# Try with --allowerasing and --nobest to be more permissive
if dnf5 -y install --allowerasing --nobest --skip-unavailable \
    "kernel-core-6.14.11*" \
    "kernel-modules-6.14.11*" \
    "kernel-modules-core-6.14.11*" \
    "kernel-modules-extra-6.14.11*" \
    "kernel-devel-6.14.11*" \
    "kernel-headers-6.14.11*"; then
    
    echo "Successfully installed kernel 6.14.11"
else
    echo "Failed to install kernel 6.14.11, trying with specific repository..."
    
    # Try with explicit repository specification
    if dnf5 -y install --allowerasing --nobest --skip-unavailable \
        --repo updates-archive \
        "kernel-core-6.14.11*" \
        "kernel-modules-6.14.11*" \
        "kernel-modules-core-6.14.11*" \
        "kernel-modules-extra-6.14.11*" \
        "kernel-devel-6.14.11*" \
        "kernel-headers-6.14.11*" 2>/dev/null; then
        
        echo "Successfully installed kernel 6.14.11 from updates-archive"
    else
        echo "Failed to install kernel 6.14.11, trying fallback approach..."
        
        # Fallback: try to install any available 6.14.x kernel
        if ! dnf5 -y install --allowerasing --nobest --skip-unavailable \
            "kernel-core-6.14.*" \
            "kernel-modules-6.14.*" \
            "kernel-modules-core-6.14.*" \
            "kernel-modules-extra-6.14.*" \
            "kernel-devel-6.14.*" \
            "kernel-headers-6.14.*"; then
            
            echo "WARNING: Could not install any 6.14.x kernel"
            echo "Available kernel versions in repository:"
            dnf5 list available "kernel-core*" || true
            echo "Continuing with existing kernel and setting up exclusions..."
        fi
    fi
fi

# Configure DNF to exclude kernel updates
echo "Configuring DNF to exclude kernel package updates..."
mkdir -p /etc/dnf

# Check if dnf.conf exists, create if not
if [ ! -f /etc/dnf/dnf.conf ]; then
    echo "[main]" > /etc/dnf/dnf.conf
    echo "gpgcheck=True" >> /etc/dnf/dnf.conf
    echo "installonly_limit=3" >> /etc/dnf/dnf.conf
    echo "clean_requirements_on_remove=True" >> /etc/dnf/dnf.conf
    echo "best=False" >> /etc/dnf/dnf.conf
    echo "skip_if_unavailable=True" >> /etc/dnf/dnf.conf
fi

# Add or update exclude line
if grep -q "^exclude=" /etc/dnf/dnf.conf; then
    # Update existing exclude line
    sed -i "s/^exclude=.*/exclude=$EXCLUDE_PACKAGES/" /etc/dnf/dnf.conf
else
    # Add new exclude line
    echo "exclude=$EXCLUDE_PACKAGES" >> /etc/dnf/dnf.conf
fi

echo "DNF configuration updated to exclude: $EXCLUDE_PACKAGES"

# Also create a specific config file for ostree/rpm-ostree compatibility
cat > /etc/dnf/protected.d/kernel-downgrade.conf << EOF
# Protect against automatic kernel updates
# Generated by kernel-downgrade module
kernel-core
kernel-modules
kernel-modules-core
kernel-modules-extra
kernel-devel
kernel-headers
EOF

echo "Created DNF protected packages configuration"

# Show final status
echo "=== Final Kernel Status ==="
echo "Installed kernel packages:"
rpm -qa | grep "^kernel-" | grep -v "kernel-tools" | grep -v "kernel-firmware" | sort || echo "No kernel packages found"

echo "Available kernels in /lib/modules:"
ls -la /lib/modules/ 2>/dev/null || echo "No modules directory found yet"

echo "DNF exclude configuration:"
grep "^exclude=" /etc/dnf/dnf.conf 2>/dev/null || echo "No exclude configuration found"

echo "Kernel downgrade module completed successfully"
