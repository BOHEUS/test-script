#!/bin/bash
# Fully automated installation process from beginning to end

# Global variables
aurhelper="yay"

# Functions

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
				sed -e 's/\s*([\+0-9a-zA-Z]*\).*/\1/' << FDISK_CMDS | fdisk /dev/sda
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
				sed -e 's/\s*([\+0-9a-zA-Z]*\).*/\1/' << FDISK_CMDS | fdisk /dev/sda
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
		arch-chroot /mnt
		ln -sf /usr/share/zoneinfo/Poland
		hwclock --systohc
		vim /etc/locale.gen -c ":s/#pl_PL./pl_PL./g" -c ":wq"
		echo "LANG=pl_PL.UTF-8" >> /etc/locale.conf
		echo "KEYMAP=pl" >> /etc/vconsole.conf
		echo "Arch" >> /etc/hostname
		mkinitcpio -P
}

newuser(){
	# Creating new user and setting up basics
	name=$(whiptail --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	whiptail --infobox "Adding user \"$name\"..." 7 50
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
		usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

refreshkeys(){
case "$(readlink -f /sbin/init)" in
	*systemd*)
		whiptail --infobox "Refreshing Arch Keyring..." 7 40
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
		;;
	*)
		whiptail --infobox "Enabling Arch Repositories for more a more extensive software collection..." 7 40
		pacman --noconfirm --needed -S \
			artix-keyring artix-archlinux-support >/dev/null 2>&1
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm >/dev/null 2>&1
		pacman-key --populate archlinux >/dev/null 2>&1
		;;
	esac
}

installpkg(){
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

aurhelperinstall(){
	pacman -Qq "$1" && return 0
	whiptail --infobox "Installing \"$1\" manually." 7 50
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{
			cd "$repodir/$1" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" -D "$repodir/$1" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	# Installs all needed programs from main repo.
	whiptail --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 9 70
	installpkg "$1"
}

gitmakeinstall() {
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	whiptail --title "LARBS Installation" \
		--infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{
			cd "$dir" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	whiptail --title "LARBS Installation" \
		--infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 9 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	whiptail --title "LARBS Installation" \
		--infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 9 70
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

installationloop() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/app.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\"$" &&
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		"A") aurinstall "$program" "$comment" ;;
		"G") gitmakeinstall "$program" "$comment" ;;
		"P") pipinstall "$program" "$comment" ;;
		*) maininstall "$program" "$comment" ;;
		esac
	done </tmp/app.csv
}

multilib(){
	echo "[multilib]
Include = /etc/pacman.d/mirrorlist" > /etc/pacman.d/mirrorlist
}

end(){
	whiptail --infobox "Your computer should be now prepared for usage.\nComputer will restart in 5 seconds." 10 60
	sleep 5
	reboot
}
# Main stuff
# Checking if script is running on Arch
pacman --noconfirm --needed -Sy libnewt ||
	error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Preparing the system
beginning

# Refreshing keyrings
refreshkeys
for x in curl ca-certificates base-devel coreutils-git zsh; do
	installpkg "$x"
done

# Creating new user
newuser

# Just in case to prevent errors
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Adding user to sudoers
trap 'rm -f /etc/sudoers.d' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d

# Setting up pacman
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Speed up installation process by using all cores
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

# Install AUR helper
aurhelperinstall $aurhelper || error "Failed to install AUR helper."

# Update AUR packages on fly
$aurhelper -Y --save --devel

# Add multilib repo for steam
multilib

# Install rust language
curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh

# Install all programs
installationloop

# Install dotfiles
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Install vim plugins
[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall

# Get rid of beep (just in case)
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Change default shell to zsh for the user 
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Set up browser
whiptail --infobox "Setting browser privacy settings and add-ons..." 7 60
browserdir="/home/$name/.librewolf"
profilesini="$browserdir/profiles.ini"

# Start librewolf headless so it generates a profile. Then get that profile in a variable.
sudo -u "$name" librewolf --headless >/dev/null 2>&1 &
sleep 1
profile="$(sed -n "/Default=.*.default-default/ s/.*=//p" "$profilesini")"
pdir="$browserdir/$profile"
[ -d "$pdir" ] && makeuserjs
[ -d "$pdir" ] && installffaddons

# Kill the now unnecessary librewolf instance.
pkill -u "$name" librewolf

# Allow wheel users to sudo with password and allow several system commands
# (like `shutdown` to run without password).
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -u -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --" >/etc/sudoers.d
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

# The end
end
