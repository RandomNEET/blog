---
title: 全盘加密安装NixOS
published: 2026-01-12
description: btrfs+tmpfs
image: ./cover.png
tags: [Linux, NixOS, Filesystem, Encryption]
category: Linux
draft: false
---

# 安装前

## 联网

生成 wifi 配置文件

```sh
wpa_passphrase "WiFi_SSID" "WiFi_PASSWORD" | tee /etc/whatever.conf
```

查看设备名

```sh
ip a
```

用刚刚列出的设备通过配置文件连接 wifi

```sh
wpa_supplicant -B -i "devicename" -c /etc/whatever.conf
```

## 代理

仅作参考

```sh
nix-shell -p xray
xray run -c /path/to/config.json
export http_proxy=http://127.0.0.1:port
export https_proxy=http://127.0.0.1:port
export ALL_PROXY=socks5h://127.0.0.1:port
```

# 无休眠系统安装 (不使用 LVM)

## 格式化+分区

### 1.创建 gpt 分区表

```sh
parted /dev/sdX mklabel gpt
```

### 2.创建 UEFI FAT32 分区 (以下表示为/dev/sdXY)

```sh
parted /dev/sdX mkpart esp fat32 1MiB 512MiB
parted /dev/sdX set 1 esp on
parted /dev/sdX set 1 boot on
mkfs.fat -F 32 -n UEFI /dev/sdXY
```

### 3.创建 SWAP 分区 (以下表示为/dev/sdXW)

```sh
parted /dev/sdX mkpart swap linux-swap 512MiB 4.5GiB
mkswap -L SWAP /dev/sdXW
```

### 4.创建 NIXOS BTRFS 加密分区 (以下表示为/dev/sdXZ)

```sh
parted /dev/sdX mkpart nixos btrfs 4.5GiB 100%
cryptsetup --verify-passphrase -v luksFormat /dev/sdXZ
cryptsetup open /dev/sdXZ enc
mkfs.btrfs -L NIXOS /dev/mapper/enc
```

## 设置 BTRFS 子卷

### 1.挂载 NIXOS 分区

```sh
mount -t btrfs /dev/mapper/enc /mnt
```

### 2.创建 NIX 子卷

```sh
btrfs subvolume create /mnt/@nix
```

### 3.创建 HOME 子卷

```sh
btrfs subvolume create /mnt/@home
```

### 4.创建 snapshots 子卷 (用于 snapper 自动快照)

```sh
btrfs subvolume create /mnt/@home/.snapshots
```

### 5.卸载 NIXOS 分区

```sh
umount /mnt
```

## 挂载分区

### 1.挂载 ROOT 分区 (in-ram)

```sh
mount -t tmpfs -o noatime,mode=755 none /mnt
```

### 2.创建挂载点

```sh
mkdir /mnt/{boot,nix,home}
mkdir /mnt/home/.snapshots
```

### 3.挂载 UEFI 分区

```sh
mount -t vfat -o defaults,noatime,fmask=0077,dmask=0077 /dev/sdXY /mnt/boot
```

### 4.挂载 NIX 子卷

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@nix /dev/mapper/enc /mnt/nix
```

### 5.挂载 HOME 子卷

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home /dev/mapper/enc mnt/home
```

### 6.挂载 snapshots 子卷

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home/.snapshots /dev/mapper/enc /mnt/home/.snapshots
```

### 7.挂载 SWAP 分区

```sh
swapon /dev/sdXW
```

## 生成 NixOS 配置文件并安装

### 1.让 NixOS 生成初始配置文件

```sh
nixos-generate-config --root /mnt
```

### 2.确保 hardware-configuration.nix 里的挂载点和之前的挂载步骤一致

```sh
vim /mnt/etc/nixos/hardware-configuration.nix
```

示例

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
    {
      device = "/dev/disk/by-partuuid/XXX";
      randomEncryption.enable = true;
    }
  ];
```

> [!NOTE]
> 如果有 swap 启用了 randomEncryption, 不要使用休眠！！！
> 对于启用了 randomEncryption 的 swap, 不要使用 /dev/disk/by-uuid/… 或者 /dev/disk/by-label/… , 应该使用 /dev/disk/by-partuuid/…

### 3.编辑 configuration.nix

```sh
vim /mnt/etc/nixos/configuration.nix
```

禁用可变用户

```nix
users.mutableUsers = false;
```

- 添加用户密码(hashed):
  (在另一个终端输入: `nix-shell --run 'mkpasswd -m SHA-512 -s' -p mkpasswd`)

```nix
users.users.<USERNAME>.initialHashedPassword = "<HASHED_PASSWORD>";
```

### 4.安装 NixOS

```sh
nixos-install --no-root-passwd
reboot
```

# 带休眠系统安装 (使用 LVM)

## 格式化并分区

### 1.创建 GPT 分区表

```sh
parted /dev/sdX mklabel gpt
```

### 2.创建 UEFI FAT32 分区 (以下表示为/dev/sdXY)

```sh
parted /dev/sdX mkpart esp fat32 1MiB 512MiB
parted /dev/sdX set 1 esp on
parted /dev/sdX set 1 boot on
mkfs.fat -F 32 -n UEFI /dev/sdXY
```

### 3.为 LVM 创建加密分区 (以下表示为/dev/sdXZ)

```sh
parted /dev/sdX mkpart primary 512MiB 100%
parted /dev/sdX set 2 lvm on
cryptsetup --verify-passphrase -v luksFormat /dev/sdXZ
```

### 4.创建 LVM 逻辑卷

```sh
cryptsetup open /dev/sdXZ enc
pvcreate /dev/mapper/enc
vgcreate vg0 /dev/mapper/enc

```

### 5.创建 swap 卷 (以下表示为/dev/vg0/swap)

```sh
lvcreate -L 48G -n swap vg0
mkswap -L SWAP /dev/vg0/swap
```

### 6.创建 NixOS Btrfs 卷 (以下表示为/dev/vg0/main)

```sh
lvcreate -l 100%FREE -n main vg0
mkfs.btrfs -L NIXOS /dev/vg0/main
```

## 设置 BTRFS 子卷

### 1.挂载 NIXOS 卷

```sh
mount -t btrfs /dev/vg0/main /mnt
```

### 2.创建 NIX 子卷

```sh
btrfs subvolume create /mnt/@nix
```

### 3.创建 HOME 子卷

```sh
btrfs subvolume create /mnt/@home
```

### 4.创建 snapshots 子卷 (用于 snapper 自动快照)

```sh
btrfs subvolume create /mnt/@home/.snapshots
```

### 5.卸载 NIXOS 卷

```sh
umount /mnt
```

## 挂载分区

### 1.挂载 ROOT 分区 (in-ram)

```sh
mount -t tmpfs -o noatime,mode=755 none /mnt
```

### 2.创建挂载点

```sh
mkdir /mnt/{boot,nix,home}
mkdir /mnt/home/.snapshots
```

### 3.挂载 UEFI 分区

```sh
mount -t vfat -o defaults,noatime,fmask=0077,dmask=0077 /dev/sdXY /mnt/boot
```

### 4.挂载 NIX 子卷

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@nix /dev/vg0/main /mnt/nix
```

### 5.挂载 HOME 子卷

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home /dev/vg0/main /mnt/home
```

### 6.挂载 snapshots 子卷

```sh
mount -t btrfs -o noatime,compress=zstd,subvol=@home/.snapshots /dev/vg0/main /mnt/home/.snapshots
```

### 7.挂载 swap

```sh
swapon /dev/vg0/swap
```

## 生成 NixOS 配置文件并安装

### 1.让 NixOS 生成初始配置文件

```sh
nixos-generate-config --root /mnt
```

### 2.确保 hardware-configuration.nix 里的挂载点和之前的挂载步骤一致

```sh
vim /mnt/etc/nixos/hardware-configuration.nix
```

示例

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
> 手动添加以下内容:
>
> ```nix
> boot.initrd.luks.devices."enc".device = "/dev/disk/by-uuid/XXX";
> ```
>
> 用实际 UUID (终端输入 `blkid /dev/sdXZ` 查看) 代替 `XXX`

### 3.编辑 configuration.nix

```sh
vim /mnt/etc/nixos/configuration.nix
```

禁用可变用户

```nix
users.mutableUsers = false;
```

- 添加用户密码(hashed):
  (在另一个终端输入: `nix-shell --run 'mkpasswd -m SHA-512 -s' -p mkpasswd`)

```nix
users.users.<USERNAME>.initialHashedPassword = "<HASHED_PASSWORD>";
```

### 4.安装 NixOS

```sh
nixos-install --no-root-passwd
reboot
```

# 安装后

## 1.保存 nixos 文件夹

```sh
mkdir /mnt/nix/persist/etc
cp -r /etc/nixos /mnt/nix/persist/etc/
```

## 2.使用 [impermanence](https://nixos.wiki/wiki/Impermanence) 来保存需要的文件

添加到 flake.nix inputs

```nix
impermanence.url = "github:nix-community/impermanence";
```

configuration.nix

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

参考:

- [Install NixOS with BTRFS and IN-RAM root](https://gist.github.com/giuseppe998e/629774863b149521e2efa855f7042418)
- [NixOS on Btrfs+tmpfs](https://cnx.srht.site/blog/butter)
- [Erase your darlings](https://grahamc.com/blog/erase-your-darlings)
- [NixOS ❄: tmpfs as root](https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/)
- [Paranoid NixOS Setup](https://christine.website/blog/paranoid-nixos-2021-07-18)
