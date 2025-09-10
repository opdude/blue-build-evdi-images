# blue-build-evdi-images &nbsp; [![bluebuild build badge](https://github.com/opdude/blue-build-evdi-images/actions/workflows/build.yml/badge.svg)](https://github.com/opdude/blue-build-evdi-images/actions/workflows/build.yml)

Adds DisplayLink EVDI support for enhanced multi-monitor setups to the Bazzite and Aurora DX images.

## Features

- **DisplayLink Support**: Includes the EVDI (Extensible Virtual Display Interface) kernel module for DisplayLink devices
- **Secure Boot Compatible**: EVDI module is properly signed for Secure Boot systems
- **Automated Builds**: Daily builds with automatic stable tagging on main branch pushes

### Aurora-DX Specific Features
- **Kernel 6.14 Pinned**: Uses kernel 6.14 for compatibility with CrowdStrike Falcon sensor and other tools that require older kernel versions


## Installation

> [!WARNING]  
> These are experimental images, try at your own discretion.

To rebase an existing Bazzite installation to the EVDI images use one of the following commands based on your current variant:

**For KDE Plasma (default Bazzite):**
```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/bazzite-evdi:stable
```

**For GNOME:**
```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/bazzite-gnome-evdi:stable
```

### NVIDIA Variants

**For Bazzite KDE Plasma with NVIDIA:**
```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/bazzite-nvidia-open-evdi:stable
```

**For GNOME with NVIDIA:**
```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/bazzite-gnome-nvidia-open-evdi:stable
```

**For Aurora DX KDE Plasma with NVIDIA:**
```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/aurora-dx-nvidia-open-evdi:stable
```

### ⚠️ Important Desktop Environment Warning

**Do not switch between GNOME and KDE variants!** If you are currently running:
- **GNOME** (bazzite-gnome*): Only use the `-gnome` variants above
- **KDE Plasma** (standard bazzite): Only use the variants without `-gnome` in the name

Switching between desktop environments via rebase can break your installation and may require a complete reinstall.

After running the rebase command, reboot your system to complete the installation. 

### Secureboot

> [!NOTE]  
> If you are using secureboot, this step is essential to ensure the EVDI module loads correctly.

After the first boot, if you have secureboot enabled, you will need to enroll the DisplayLink EVDI module signing key. This is necessary for the evdi module to load correctly.

To do this, run the following command:

```bash
sudo mokutil --import /etc/pki/DisplayLink/evdi-signing-key.der
```

You will be prompted to set a password for MOK enrollment. After setting the password, reboot the system. During boot, you will see the MOK Manager screen. Select "Enroll MOK" and follow the prompts. Enter the password you set earlier to enroll the key. After this, the evdi module should load correctly.

### Kernel Version

The Aurora-DX image is configured to use kernel 6.14 instead of the latest available kernel. This provides compatibility with security tools like CrowdStrike Falcon sensor due to changes in BPF.
## Development

### Building Locally

You can build the image locally using the provided scripts:

```bash
# Or build using Docker (no kernel headers needed)
./scripts/build-evdi-docker.sh

# Then build the image
bluebuild build recipes/recipe.yml
```

### Prebuilt Modules

Note: The following is only needed for local development as the github actions will automatically build the prebuilt modules.

The image supports prebuilt EVDI modules. Place them in `files/prebuilt-modules/` with the naming convention:
```
evdi-<kernel-version>-<arch>.ko
```

For example: `evdi-6.11.0-68.fc40.x86_64-x86_64.ko`

#### Building Prebuilt Modules

First, we need to switch to the latest aurora-dx-nvidia-open image to get the latest kernel headers:

```
rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/aurora-dx-nvidia-open:stable
```

Then, build the prebuilt modules using the provided script:

```bash
./scripts/build-evdi-docker.sh
```

Add the package to the `files/prebuilt-modules/` directory, and then build the image with the following command to check it works:

```bash
bluebuild build recipes/recipe.yml
```

## Contributing

See the [BlueBuild docs](https://blue-build.org/how-to/setup/) for more information about customizing and contributing to this image.

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/learn/universal-blue/#fresh-install-from-an-iso). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/opdude/op-aurora-dx-nvidia-open
```
