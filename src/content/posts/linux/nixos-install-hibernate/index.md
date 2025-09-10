---
title: Install NixOS with encrypted Btrfs and a IN-RAM root (with hibernation)
published: 2025-09-10
description: This is how I installed NixOS on my laptop.
image: ./cover.png
tags: [Linux, NixOS, Installation, Filesystem, Encryption]
category: Linux
draft: false
---

# 1. Format and partition

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

## 3.Create an encrypted partition for LVM (which will be /dev/sdXZ)

```sh
parted /dev/sdX mkpart primary 512MiB 100%
parted /dev/sdX set 2 lvm on
cryptsetup --verify-passphrase -v luksFormat /dev/sdXZ
```

## 4.Create LVM volumes

```sh
cryptsetup open /dev/sdXZ enc
pvcreate /dev/mapper/enc
vgcreate vg0 /dev/mapper/enc

```

## 5.Create the swap volume (which will be /dev/vg0/swap)

```sh
lvcreate -L 48G -n swap vg0
mkswap -L SWAP /dev/vg0/swap
```

## 6.Create the NixOS Btrfs volume (which will be /dev/vg0/main)

```sh
lvcreate -l 100%FREE -n main vg0
mkfs.btrfs -L NIXOS /dev/vg0/main
```

# 2. Setup BTRFS subvolumes

## 1.Mount the NIXOS volume

```sh
mount -t btrfs /dev/vg0/main /mnt
```

## 2.Create the NIX subvolume

```sh
btrfs subvolume create /mnt/@nix
```

## 3.Create the HOME subvolume

```sh
btrfs subvolume create /mnt/@home
```

## 4.Create the snapshots subvolume

```sh
btrfs subvolume create /mnt/@home/.snapshots
```

## 5.Unmount the NIXOS volume

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

## 4.Mount the NIX subvolume

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@nix /dev/vg0/main /mnt/nix
```

## 5.Mount the HOME subvolume

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home /dev/vg0/main /mnt/home
```

## 6.Mount the SNAPSHOTS subvolume

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home/.snapshots /dev/vg0/main /mnt/home/.snapshots
```

## 7.Mount swap

```sh
swapon /dev/vg0/swap
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
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "noatime"
      "size=3G"
      "mode=755"
    ];
  };

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
      "noatime"
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
    { device = "/dev/disk/by-uuid/XXX"; }
  ];
```

> [!NOTE]
> Add the following line manually:
>
> ```nix
> boot.initrd.luks.devices."enc".device = "/dev/disk/by-uuid/XXX";
> ```
>
> Replace `XXX` with the actual UUID (check with `blkid /dev/sdXZ`).  
> Without this line, the system will not boot.

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
