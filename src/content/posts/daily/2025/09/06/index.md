---
title: Unable to start VMs after flake update
published: 2025-09-06
description: VMs fail to start due to changed QEMU firmware path after flake update.
image: ./cover.png
tags: [Daily, NixOS, Virtualization]
category: Daily
draft: false
---

# Issue

When attempting to start any virtual machines, the following critical error occurs:

```log
Error starting domain: operation failed: Unable to find 'efi' firmware that is compatible with the current configuration
```

This prevents all VMs from starting. The full traceback from virt-manager is shown below:

```log
Error starting domain: operation failed: Unable to find 'efi' firmware that is compatible with the current configuration

Traceback (most recent call last):
  File "/nix/store/pwsbb36h2jj1vq1k8dvwxsbmf9kqnpx3-virt-manager-5.0.0/share/virt-manager/virtManager/asyncjob.py", line 71, in cb_wrapper
    callback(asyncjob, *args, **kwargs)
    ~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/nix/store/pwsbb36h2jj1vq1k8dvwxsbmf9kqnpx3-virt-manager-5.0.0/share/virt-manager/virtManager/asyncjob.py", line 107, in tmpcb
    callback(*args, **kwargs)
    ~~~~~~~~^^^^^^^^^^^^^^^^^
  File "/nix/store/pwsbb36h2jj1vq1k8dvwxsbmf9kqnpx3-virt-manager-5.0.0/share/virt-manager/virtManager/object/libvirtobject.py", line 57, in newfn
    ret = fn(self, *args, **kwargs)
  File "/nix/store/pwsbb36h2jj1vq1k8dvwxsbmf9kqnpx3-virt-manager-5.0.0/share/virt-manager/virtManager/object/domain.py", line 1384, in startup
    self._backend.create()
    ~~~~~~~~~~~~~~~~~~~~^^
  File "/nix/store/yhwvyjphkjmwwlfs2li36rxj9zkka7jp-python3.13-libvirt-11.6.0/lib/python3.13/site-packages/libvirt.py", line 1390, in create
    raise libvirtError('virDomainCreate() failed')
libvirt.libvirtError: operation failed: Unable to find 'efi' firmware that is compatible with the current configuration
```

# Cause

After a flake update, the path to qemu-system-x86_64 changed.
The VM XML configuration still pointed to the old /nix/store/... firmware files, so libvirt failed to locate the EFI firmware.

Here is an example of the old XML snippet (no longer valid):

```xml
<os firmware="efi">
  <type arch="x86_64" machine="pc-q35-10.0">hvm</type>
  <firmware>
    <feature enabled="no" name="enrolled-keys"/>
    <feature enabled="yes" name="secure-boot"/>
  </firmware>
  <loader readonly="yes" secure="yes" type="pflash" format="raw">
    /nix/store/gc3xfs807jz08hd88mjy055fyhiifhxy-qemu-host-cpu-only-10.0.2/share/qemu/edk2-x86_64-secure-code.fd
  </loader>
  <nvram template="/nix/store/gc3xfs807jz08hd88mjy055fyhiifhxy-qemu-host-cpu-only-10.0.2/share/qemu/edk2-i386-vars.fd"
         templateFormat="raw"
         format="raw">
    /var/lib/libvirt/qemu/nvram/win11-ltsc_VARS.fd
  </nvram>
  <boot dev="hd"/>
</os>
```

# Solution

1. Find the current path of `qemu-system-x86_64` in your Nix store:

```sh
nix-store -q $(which qemu-system-x86_64)
```

2. Update the VM XML so that the `<loader>` and `<nvram>` entries point to the new paths:

```xml
<os firmware="efi">
  <type arch="x86_64" machine="pc-q35-10.0">hvm</type>
  <firmware>
    <feature enabled="no" name="enrolled-keys"/>
    <feature enabled="yes" name="secure-boot"/>
  </firmware>
  <loader readonly="yes" secure="yes" type="pflash" format="raw">
    /nix/store/8fg38774hh8mysi8f0a259762i4mcgzx-qemu-host-cpu-only-10.0.3/share/qemu/edk2-x86_64-secure-code.fd
  </loader>
  <nvram template="/nix/store/8fg38774hh8mysi8f0a259762i4mcgzx-qemu-host-cpu-only-10.0.3/share/qemu/edk2-i386-vars.fd"
         templateFormat="raw"
         format="raw">
    /var/lib/libvirt/qemu/nvram/win11-ltsc_VARS.fd
  </nvram>
  <boot dev="hd"/>
</os>
```
