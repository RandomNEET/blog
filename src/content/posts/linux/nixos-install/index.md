---
title: Install NixOS
published: 2025-07-22
description: Install NixOS with full-disk encryption on Btrfs and a RAM-based root.
image: ./cover.png
tags: [Linux, NixOS, Installation, Filesystem, Encryption]
category: Linux
draft: false
---

# 0.Pre-installation

## 1.Connect to the internet

- Generate configuration file

```sh
wpa_passphrase "WiFi_SSID" "WiFi_PASSWORD" | tee /etc/whatever.conf
```

- Check the device name

```sh
ip a
```

- Connect to the network

```sh
wpa_supplicant -B -i "devicename" -c /etc/whatever.conf
```

## 2.Proxy (optional)

```sh
nix-shell -p xray
xray run -c /path/to/config.json
export http_proxy=http://127.0.0.1:port
export https_proxy=http://127.0.0.1:port
export ALL_PROXY=socks5h://127.0.0.1:port
```

# 1.Format and partition

## 1.Create the GPT partition table

```sh
parted /dev/sdX mklabel gpt
```

## 2.Create the UEFI FAT32 partition (which will be /dev/sdXY)

```sh
parted /dev/sdX mkpart esp fat32 1MiB 512MiB
parted /dev/sdX set 1 esp on
parted /dev/sdX set 1 boot on
mkfs.fat -F 32 -n UEFI /dev/sdXY
```

## 3.Create the SWAP partition (which will be /dev/sdXW) (optional)

```sh
parted /dev/sdX mkpart swap linux-swap 512MiB 4.5GiB
mkswap -L SWAP /dev/sdXW
```

## 4.Create the NIXOS BTRFS partition with encryption (which will be /dev/sdXZ)

```sh
parted /dev/sdX mkpart nixos btrfs 4.5GiB 100%
cryptsetup --verify-passphrase -v luksFormat /dev/sdXZ
cryptsetup open /dev/sdXZ enc
mkfs.btrfs -L NIXOS /dev/mapper/enc
```

# 2. Setup BTRFS subvolumes

## 1.Mount the NIXOS partition

```sh
mount -t btrfs /dev/mapper/enc /mnt
```

## 2.Create the NIX partition subvolume

```sh
btrfs subvolume create /mnt/@nix
```

## 3.Create the HOME partition subvolume

```sh
btrfs subvolume create /mnt/@home
```

## 4.Create the snapshots subvolume

```sh
btrfs subvolume create /mnt/@home/.snapshots
```

## 5.Unmount the NIXOS partition

```sh
umount /mnt
```

# 3. Mount the partitions for installation

## 1.Mount the in-ram ROOT partition

```sh
mount -t tmpfs -o noatime,mode=755 none /mnt
```

## 2.Create persistent directories on which to mount partitions

```sh
mkdir /mnt/{boot,nix,home}
mkdir /mnt/home/.snapshots
```

## 3.Mount the UEFI partition

```sh
mount -t vfat -o defaults,noatime,fmask=0077,dmask=0077 /dev/sdXY /mnt/boot
```

## 4.Mount the NIX partition subvolume

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@nix /dev/mapper/enc /mnt/nix
```

## 5.Mount the HOME partition subvolume

```sh
mount -t btrfs -o compress=zstd,subvol=@home /dev/mapper/enc mnt/home
```

## 6.Mount the SNAPSHOTS partition subvolume

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home/.snapshots /dev/sdXZ /mnt/home/.snapshots
```

## 7.Mount the SWAP partition (optional)

```sh
swapon /dev/sdXW
```

# 4. Generate NixOS configs & install

## 1.Let NixOS generate template configurations

```sh
nixos-generate-config --root /mnt
```

## 2.Make sure all mount points in hardware-configuration.nix are identical to the previous section

```sh
vim /mnt/etc/nixos/hardware-configuration.nix
```

- Example

```nix
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/XXX";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  boot.initrd.luks.devices."enc".device = "/dev/disk/by-uuid/XXX";

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/XXX";
    fsType = "btrfs";
    options = [
      "subvol=@nix"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/XXX";
    fsType = "btrfs";
    options = [
      "subvol=@home"
      "compress=zstd"
    ];
  };

  fileSystems."/home/.snapshots" = {
    device = "/dev/disk/by-uuid/XXX";
    fsType = "btrfs";
    options = [
      "subvol=@home/.snapshots"
      "compress=zstd"
      "noatime"
    ];
  };

  swapDevices = [
    {
      device = "/dev/disk/by-partuuid/XXX";
      randomEncryption.enable = true;
    }
  ];
```

> [!NOTE]
> Don't try to hibernate when you have at least one swap partition with randomEncryption enabled! We have no way to set the partition into which hibernation image is saved, so if your image ends up on an encrypted one you would lose it!
>
> Do not use /dev/disk/by-uuid/… or /dev/disk/by-label/… as your swap device when using randomEncryption as the UUIDs and labels will get erased on every boot when the partition is encrypted. Best to use /dev/disk/by-partuuid/…

## 3.Edit the configuration.nix file as needed

```sh
vim /mnt/etc/nixos/configuration.nix
```

- Disable users mutability:

```nix
users.mutableUsers = false;
```

- Add user (hashed) password:
  (In another console: `nix-shell --run 'mkpasswd -m SHA-512 -s' -p mkpasswd`)

```nix
users.users.<USERNAME>.initialHashedPassword = "<HASHED_PASSWORD>";
```

## 4.Start the installer

```sh
nixos-install --no-root-passwd
reboot
```

# 5. Post-installation

## 1.Keep nixos folder

```sh
mkdir /mnt/nix/persist/etc
cp -r /etc/nixos /mnt/nix/persist/etc/
```

## 2.Use [impermanence](https://nixos.wiki/wiki/Impermanence) to persist necessary files

- Add to flake.nix inputs

```nix
impermanence.url = "github:nix-community/impermanence";
```

- configuration.nix

```nix
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  # persist
  imports = [ inputs.impermanence.nixosModules.impermanence ];
  environment.persistence."/nix/persist" = {
    hideMounts = true;
    directories = (
      [
        "/var/log"
        "/var/lib/nixos"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/timers"
        "/var/lib/bluetooth"
        "/etc/nixos"
        "/etc/NetworkManager/system-connections"
        {
          directory = "/var/lib/colord";
          user = "colord";
          group = "colord";
          mode = "u=rwx,g=rx,o=";
        }
      ]
      ++ lib.optional config.virtualisation.libvirtd.enable "/var/lib/libvirt"
    );
    files = (
      [
        "/etc/machine-id"
        {
          file = "/etc/nix/id_rsa";
          parentDirectory = {
            mode = "u=rwx,g=rx,o=rx";
          };
        }
      ]
      ++ lib.optionals config.services.openssh.enable [
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ]
    );
  };
  security.sudo.extraConfig = ''
    Defaults lecture = never
  '';
}
```

---

Reference:

- [Install NixOS with BTRFS and IN-RAM root](https://gist.github.com/giuseppe998e/629774863b149521e2efa855f7042418)
- [NixOS on Btrfs+tmpfs](https://cnx.srht.site/blog/butter)
- [Erase your darlings](https://grahamc.com/blog/erase-your-darlings)
- [NixOS ❄: tmpfs as root](https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/)
- [Paranoid NixOS Setup](https://christine.website/blog/paranoid-nixos-2021-07-18)
