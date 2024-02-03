#!/bin/bash

beginning(){
		whiptail --title "Hello there" \
		--msgbox "This script will prepare your system from beginning to the end so you won't have to worry about setting it up by yourself" 10 60
		# Loading specific keyboard layout
		loadkeys pl
		# Updating system clock
		whiptail --infobox "Synchronizing system clock" 7 50
		timedatectl set-ntp true
		echo "NTP=vega.cbk.poznan.pl" >> /etc/systemd/timesyncd.conf
		timedatectl set-timezone Europe/Warsaw
		systemctl restart systemd-timesyncd.service
		whiptail --infobox "Partitioning, formatting and mounting your disk" 7 50
		bios=`cat /sys/firmware/efi/fw_platform_size`
		# Checking if BIOS is UEFI
		if [ $bios = 64 ]; then
				# Partitioning disk
				sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << FDISK_CMDS | fdisk /dev/sda
				g		# new GPT partition
				n		# add new partition UEFI
				1		# partition number
						# first sector
				+1GiB	# size
				n		# add new partition swap
				2		# partition number
						# first sector
				+20GiB	# size
				n		# add new partition
				3		# partition number
						# first sector
						# size is rest of free space
				t		# partition type
				1		# first partition
				uefi	# UEFI
				t		# partition type
				2		# second partition
				swap	# swap
				t		# partition type
				3		# third partition
				linux	# linux filesystem
				w		# write partition table and exit
FDISK_CMDS
				# Formatting partitions
				mkfs.fat -F 32 /dev/sda1	# UEFI partition
				mkswap /dev/sda2 			# swap partition
				mkfs.btrfs /dev/sda3		# main partition
				# Mounting partitions
				mount /dev/sda3 /mnt		# main partition
				mount --mkdir /dev/sda1 /mnt/boot	# UEFI
				swapon /dev/sda2 			# swap
				# BIOS is not UEFI
		elif [ $bios = 32 ]; then
				# Partitioning disk (fix it - to do)
				sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << FDISK_CMDS | fdisk /dev/sda
				o		# new GPT partition
				n
				p		# add new partition UEFI
				1		# partition number
						# first sector
				+1GiB	# size
				n
				p		# add new partition swap
				2		# partition number
						# first sector
						# size is rest of free space
				a
				1
				p
				w		# write partition table and exit
FDISK_CMDS
				# Formatting partitions
				mkswap /dev/sda1 			# swap partition
				mkfs.btrfs /dev/sda2		# main partition
				# Mounting partitions
				mount /dev/sda2 /mnt		# main partition
				swapon /dev/sda1 			# swap
		fi
		# Installing necessities
		whiptail --infobox "Installing most basic packages" 7 50
		pacstrap -K /mnt base linux-hardened linux-firmware vim
		# Configuring the system
		whiptail --infobox "Configuring the system" 7 50
		genfstab -U /mnt >> /mnt/etc/fstab
		# arch-chroot /mnt
		ln -sf /mnt/usr/share/zoneinfo/Poland /mnt/etc/localtime
		chroot /mnt /bin/bash -c "hwclock --systohc"
		vim /mnt/etc/locale.gen -c ":s/#pl_PL./pl_PL./g" -c ":wq"
		echo "LANG=pl_PL.UTF-8" >> /mnt/etc/locale.conf
		echo "KEYMAP=pl" >> /mnt/etc/vconsole.conf
		echo "Arch" >> /mnt/etc/hostname
		mkinitcpio -P
		curl https://raw.githubusercontent.com/BOHEUS/test-script/main/skrypt.sh > /mnt/skrypt.sh
		chmod +x /mnt/skrypt.sh
		curl https://raw.githubusercontent.com/BOHEUS/test-script/main/app.csv > /mnt/progs.csv
		arch-chroot /mnt /bin/bash -c "./skrypt.sh"
}

beginning
