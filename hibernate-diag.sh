#!/bin/bash
#
# Hibernate Diagnosis
# https://github.com/ProtoFoo/hibernate-diag
# Dependencies: awk, grep, lsblk, free, (uname)
#

NORMAL=$(echo -en '\001\033[0m\002')
WHITE=$(echo -en '\001\033[01;37m\002')
RED=$(echo -en '\001\033[01;31m\002')
GREEN=$(echo -en '\001\033[01;32m\002')
YELLOW=$(echo -en '\001\033[01;33m\002')

PASS=" ${GREEN}OK${NORMAL} "
FAIL="${RED}FAIL${NORMAL}"
WARN="${YELLOW}WARN${NORMAL}"

# Source: https://stackoverflow.com/a/53798785
function is_bin_in_path {
	builtin type -P "$1" &> /dev/null
}

# Source: https://stackoverflow.com/a/20460402
function is_in_string {
	[ -z "$1" ] || { [ -z "${2##*$1*}" ] && [ -n "$2" ]; }
}

function check_exit_code {
	[ $? -eq 0 ] && result="$PASS" || result="$FAIL"
	echo "  [$result] $1 resume module"
}


#############################################################################
if [ -f /etc/os-release ]; then
	. /etc/os-release
	dist_name="$PRETTY_NAME"
	[ -z "$dist_name" ] && dist_name="$NAME"

	if [ -n "$dist_name" ]; then
		echo
		echo -n "${WHITE}Distribution:${NORMAL} "
		[ -n "$ANSI_COLOR" ] && echo -en "\033[${ANSI_COLOR}m"
		echo "$dist_name${NORMAL}"
	fi
fi


#############################################################################
echo
echo "${WHITE}Kernel information${NORMAL}"

echo -n "  Version: "
uname -r

power_state=$(</sys/power/state)
is_in_string "disk" "$power_state" && result="$PASS" || result="$FAIL"
echo "  [$result] /sys/power/state:  $power_state"

result="$FAIL"
disk_state=""
if [ -e /sys/power/disk ]; then
	disk_state=$(</sys/power/disk)
	if [ -n "$disk_state" ] && [ "$disk_state" != "[disabled]" ]; then
		result="$PASS"
	fi
fi
echo "  [$result] /sys/power/disk:   $disk_state"

resume_device=$(</sys/power/resume)
resume_offset=""
[ -e /sys/power/resume_offset ] && resume_offset=$(</sys/power/resume_offset)
if [ -n "$resume_device" ]; then
	resume_uuid=$(lsblk -o MAJ:MIN,UUID | grep "$resume_device" | awk '{printf("(UUID %s)", $2)}')
	[ "$resume_device" != "0:0" ] && result="$PASS" || result="$FAIL"
	echo "  [$result] /sys/power/resume: $resume_device $resume_uuid"

	if [ -z "$resume_offset" ]; then
		echo "         /sys/power/resume_offset not found"
	else
		echo "         /sys/power/resume_offset: $resume_offset"
		[ "$resume_offset" != "0" ] && echo "         You are resuming from a file. You know what you are doing."
	fi
else
	echo "  [$FAIL] /sys/power/resume not found or empty. Kernel might not support resume."
fi

kernel_cmdline=$(</proc/cmdline)
is_in_string "resume=" "$kernel_cmdline" && result="$PASS" || result="$FAIL"
kresume=""
kresume_offset=""
# Source: https://stackoverflow.com/a/15027935
for x in $kernel_cmdline; do
	case "$x" in
	resume=*)
		kresume="${x#resume=}"
		;;
	resume_offset=*)
		kresume_offset="${x#resume_offset=}"
		;;
	esac
done
[ -n "$kresume_offset" ] && kresume_offset="(offset $kresume_offset)"
echo "  [$result] /proc/cmdline:     resume=$kresume $kresume_offset"


#############################################################################
echo
echo "${WHITE}Secure Boot state${NORMAL}"

if [ -d /sys/firmware/efi ]; then
	secure_boot=0
	lockdown=0

	if is_bin_in_path mokutil; then
		sb_state=$(mokutil --sb-state 2>&1)
		is_in_string "SecureBoot disabled" "$sb_state" && echo "  [$PASS] Secure Boot is DISABLED"
		is_in_string "SecureBoot enabled" "$sb_state" && secure_boot=1 && echo "  Secure Boot is ENABLED"
		# exit code 255
		is_in_string "This system doesn't support Secure Boot" "$sb_state" && echo "  [$PASS] Secure Boot not supported"
	else
		if is_bin_in_path journalctl; then
			sb_journal=$(journalctl -k -b -q | grep 'kernel: Secure boot ')
			is_in_string "kernel: Secure boot disabled" "$sb_journal" && echo "  [$PASS] Secure Boot is DISABLED"
			is_in_string "kernel: Secure boot enabled" "$sb_journal" && secure_boot=1 && echo "  Secure Boot is ENABLED"
		fi
	fi

	if [ -e /sys/kernel/security/lockdown ]; then
		kernel_lockdown=$(</sys/kernel/security/lockdown)
		#kernel_lockdown="none [integrity] confidentiality"
		is_in_string "\[none\]" "$kernel_lockdown" || lockdown=1
		result="$PASS"
		[ $secure_boot -eq 1 ] && [ $lockdown -eq 1 ] && result="$FAIL"
		[ $secure_boot -eq 0 ] && [ $lockdown -eq 1 ] && result="$WARN"
		echo "  [$result] /sys/kernel/security/lockdown: $kernel_lockdown"

		if [ $secure_boot -eq 1 ] && [ $lockdown -eq 0 ]; then
			echo "  Secure Boot is enabled but the Kernel is not in lockdown mode."
			echo "  Using hibernation can have security implications: man kernel_lockdown.7"
		fi
	fi
else
	echo "  [$PASS] Legacy BIOS mode, Secure Boot not supported"
fi


#############################################################################
echo
echo "${WHITE}Swap settings${NORMAL}"

mem_size=$(free -m | grep 'Mem:' | awk '{print $2}')
swap_size=$(free -m | grep 'Swap:' | awk '{print $2}')
echo "  Memory: $mem_size MB, Swap: $swap_size MB"

swap_parts=$(lsblk -l -o NAME,MAJ:MIN,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep swap | grep -v '^zram')
if [ -z "$swap_parts" ]; then
	echo "  No swap partitions found"
else
	num_swap=$(echo "$swap_parts" | wc -l)
	echo "  $num_swap swap partition(s) available:"
	echo "$swap_parts"
fi

active_swaps=$(awk 'NR>1 {print $0}' /proc/swaps | grep -v '^/dev/zram' | wc -l)
[ $active_swaps -ne 0 ] && result="$PASS" || result="$FAIL"
active_swaps_names=$(awk 'NR>1 {print $1}' ORS=' ' /proc/swaps)
echo "  [$result] $active_swaps active persistent swap location(s) $active_swaps_names"

resume_device_info=$(lsblk -lpo MAJ:MIN,NAME,TYPE,FSTYPE,MOUNTPOINT | grep "$resume_device")
if [ "$resume_device" = "0:0" ] || [ -z "$resume_device" ] || [ -z "$resume_device_info" ]; then
	echo "  [$FAIL] No location for the hibernation image found"
else
	resume_device_path=$(lsblk -lpo NAME,MAJ:MIN | grep "$resume_device" | awk '{print $1}')
	if [ -z "$resume_offset" ] || [ "$resume_offset" = "0" ]; then
		if is_in_string "$resume_device_path" "$active_swaps_names"; then
			echo "  [$PASS] The hibernation image will be written to: $resume_device_info"
		else
			echo "  [$WARN] Suspend to disk might fail. Device not found among swap locations:"
			echo "         $resume_device_info"
		fi
	else
		echo "  [$PASS] The hibernation image will be written to: $resume_device_info"
	fi
fi


#############################################################################
echo
echo "${WHITE}Initial RAM file system resume support${NORMAL}"

initram_check=0

# openSUSE, Fedora, ...
if is_bin_in_path dracut; then
	dracut --list-modules -q | grep -q resume
	check_exit_code "dracut"
	initram_check=1
fi

# Arch btw
if is_bin_in_path mkinitcpio; then
	mkinitcpio -L | grep -q resume
	check_exit_code "mkinitcpio"
	initram_check=1
fi

# Debian / Ubuntu / Mint, ...
if is_bin_in_path lsinitramfs; then
	initrd_file="/initrd.img"
	[ -f "/boot/initrd.img" ] && initrd_file="/boot/initrd.img"
	lsinitramfs -l "$initrd_file" | grep -q '/resume$'
	check_exit_code "lsinitramfs"
	initram_check=1
fi

[ $initram_check -eq 0 ] && echo "  [$WARN] Unable to detect initial RAM file system image"


echo
exit 0
