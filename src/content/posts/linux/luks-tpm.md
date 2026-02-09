---
title: 使用TPM解锁加密磁盘
published: 2026-02-09
description: 在 NixOS 上配置TPM自动解锁
tags: [Linux, NixOS, Encryption]
category: Linux
draft: false
---

# 检查 TPM 是否开启

在终端输入以下命令检查系统是否开启 TPM

```sh
ls -l /dev/tpm*
```

如果系统识别到了 TPM 应该有以下输出

```sh
crw-------    10,224 root  9 Feb 17:42 󰡯 /dev/tpm0
crw------- 248,65536 root  9 Feb 17:42 󰡯 /dev/tpmrm0
```

# 更改密钥

:::caution
建议先添加临时密钥，确认可用后再删除旧密钥，防止操作中断导致磁盘锁死

```sh
sudo cryptsetup luksAddKey /dev/nvme0n1p1 --key-slot 3 # 添加临时密钥
sudo cryptsetup luksKillSlot /dev/nvme0n1p1 3 # 删除临时密钥
```

:::

更改 slot0 旧密钥

```sh
sudo cryptsetup luksKillSlot /dev/nvme0n1p1 0
sudo cryptsetup luksAddKey /dev/nvme0n1p1 --key-slot 0
```

# 添加备用密钥

生成密钥

```sh
openssl rand -base64 48 > key.txt
```

添加密钥到 slot2

```sh
sudo cryptsetup luksAddKey /dev/nvme0n1p1 key.txt --key-slot 2
```

:::note
事后记得删除 key.txt
:::

# TPM + PIN 双因子认证

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 --tpm2-with-pin=yes /dev/nvme0n1p1
```

- --tpm2-device=auto：自动识别并调用主板上的 TPM 2.0 硬件

- --tpm2-pcrs=0+7：将解锁权限绑定到 BIOS 固件 (PCR 0) 和 安全启动状态 (PCR 7)，防止硬件或启动环境被篡改

- --tpm2-with-pin=yes：在硬件校验的基础上增加 PIN 码验证，防止电脑丢失后被直接破解

# 检查 luks 状态

```sh
sudo cryptsetup luksDump /dev/nvme0n1p1
```

# hardware-configuration.nix 配置

```nix
boot.initrd = {
  systemd.enable = true;
  luks.devices."enc" = {
    device = "/dev/disk/by-uuid/XXXX";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
};
```

:::note
建议给挂载在该磁盘下的其他分区的 options 添加 "x-systemd.device-timeout=0" 参数，防止系统在长时间未输入密码时进入紧急模式
:::

> ```nix
> fileSystems."/nix" = {
>   device = "/dev/disk/by-uuid/XXXX";
>   fsType = "btrfs";
>   options = [
>     "subvol=@nix"
>     "compress=zstd"
>     "noatime"
>     "x-systemd.device-timeout=0" # wait for decryption
>   ];
> };
> ```
