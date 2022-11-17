# Hibernate Diag

This Bash script will check various system settings to show the most common reasons that will prevent suspend to disk (hibernation).

It should run with normal user permissions on many common Linux distributions.

It was tested with:

* Arch
* Fedora
* openSUSE
* Linux Mint
* Xubuntu

---

### How to make suspend to disk working

The following must be considered:

1.  Hardware Support  
    The Linux Kernel has to support a lot of different devices.
    There is always a chance that a badly written driver or buggy firmware will make it impossible for a system to successfully suspend or to resume.
    The Linux Kernel provides a very good description of how to test if a system is capable of hibernation:
    https://www.kernel.org/doc/Documentation/power/basic-pm-debugging.txt

2.  Swap Storage  
    The system must be configured to have sufficient swap space available on a **persistent** storage device.
    Parts of the RAM currently in use will be suspended (written) to disk.
    [Zram](https://www.kernel.org/doc/Documentation/blockdev/zram.txt) would **not** usually qualify as hibernation device.

    A method exists to enable persistent swap storage just for suspending and disabling it right after resuming. It is not covered here.

3.  Resume  
    On startup the Kernel and initial RAM file system must support locating and loading a saved state (resuming) from a storage device.
    This is usually done by modifying the boot loader configuration which provides the default Kernel command line.

4.  Secure Boot  
    Resuming replaces the freshly booted Kernel in memory with the Kernel from the hibernation image.
    This can break the Secure Boot chain if certain lockdown policies are enabled and the hibernation image is not protected against tampering in a way that the freshly booted Kernel can verify.
    One way to deal with this is to simply disable Secure Boot.

---

### Script execution examples

![Archcraft](/img/archcraft.png)
![EndeavourOS](/img/endeavouros.png)
![Linux Mint](/img/linux-mint.png)
![openSUSE](/img/opensuse.png)
![Xubuntu](/img/xubuntu.png)
![Fedora](/img/fedora.png)

Note that the last image shows an example where the Kernel lockdown policy disables suspend to disk because Secure Boot is enabled.
