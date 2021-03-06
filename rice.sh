#!/bin/sh

dotfiles_repo="https://github.com/bulirma/dotfiles.git"
pkg_list="https://raw.githubusercontent.com/bulirma/artir/main/packlist.csv"

while getopts ":d:p:h" o; do case "${o}" in
	h) printf 'Optional arguments:\n\t-d: dotfiles repository \n\t-p: package list in csv\n' && exit 0 ;;
	d) dotfiles_repo=${OPTARG} || exit 1 ;;
	p) pkg_list=${OPTARG} ;;
	*) printf 'Invalid option: -%s\n' "$OPTARG" && exit 1 ;;
esac done


exit_with_error() {
	clear
	echo "$1" >&2
	exit 1
}

system_beep_off() {
	rmmod pcspkr
	echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf
}

enable_arch_repos() {
	pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >/dev/null 2>&1
	for repo in extra community multilib; do
		grep -q "\[$repo\]" /etc/pacman.conf || printf "\n[%s]\nInclude = /etc/pacman.d/mirrorlist-arch\n" "$repo" >>/etc/pacman.conf
	done
	pacman -Sy >/dev/null 2>&1
	pacman-key --populate archlinux >/dev/null 2>&1
}

install_pkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

install_base() {
	for pkg in base-devel git curl zsh go; do
		install_pkg "$pkg"
	done
}

install_yay() {
	sudo -u "$username" mkdir -p "/home/$username/.local/src"
	sudo -u "$username" git clone --depth 1 "https://aur.archlinux.org/yay.git" "/home/$username/.local/src/yay" >/dev/null 2>&1 ||
		{ cd "/home/$username/.local/src/yay" || return 1; sudo -u "$username" git pull --force origin master; }
	sudo -u "$username" -D "/home/$username/.local/src/yay" makepkg --noconfirm -si >/dev/null 2>&1
}

install_aur_pkg() {
	sudo -u "$username" yay --noconfirm -S "$1" >/dev/null 2>&1
}

install_make_git_pkg() {
	pkg="$(basename "$1" ".git")"
	sudo -u "$username" mkdir -p "/home/$username/.local/src/$pkg"
	sudo -u "$username" git clone --depth 1 "$1" "/home/$username/.local/src/$pkg" >/dev/null 2>&1
	make -C "/home/$username/.local/src/$pkg" >/dev/null 2>&1
	make -C "/home/$username/.local/src/$pkg" install >/dev/null 2>&1
}

install_pkgs() {
	sudo -u "$username" mkdir -p "/home/$username/.local/src"
	list_file="$(mktemp)"
	[ -f "$1" ] && cp "$1" "$list_file" || curl -Ls "$1" >"$list_file"
	total="$(wc -l "$list_file" | cut -d' ' -f1)"
	counter=1
	while IFS=, read -r type pkg; do
		dialog --title "Package installation" --infobox "Installing $pkg ($counter/$total)." 5 60
		case "$type" in
			"a") install_aur_pkg "$pkg" ;;
			"g") install_make_git_pkg "$pkg" ;;
			*) install_pkg "$pkg" ;;
		esac
		counter=$(( counter + 1))
	done <"$list_file"
}

install_dotfiles() {
	tmp_dir="$(sudo -u "$username" mktemp -d)"
	sudo -u "$username" git clone --depth 1 "$1" "$tmp_dir" >/dev/null 2>&1
	sudo -u "$username" cp -rfT "$tmp_dir" "/home/$username"
}

check_user_existence() {
	id -u "$1" >/dev/null 2>&1 &&
	dialog --colors --title "Warning" --yes-label "Continue" --no-label "Abort" --yesno "User $1 already exists. If you choose to continue, files in your home directory can be overwritten." 12 64 || return 1
}

add_user() {
	useradd -mG wheel -s /bin/zsh "$1" >/dev/null 2>&1 || return 1
	pw="$(dialog --no-cancel --passwordbox "Type your password:" 8 48 3>&1 1>&2 2>&3 3>&1)"
	pwconfirm="$(dialog --no-cancel --passwordbox "Retype your password:" 8 48 3>&1 1>&2 2>&3 3>&1)"
	while [ "$pw" != "$pwconfirm" ]; do
		unset pwconfirm
		pw="$(dialog --no-cancel --passwordbox "Passwords don't match. Type your password again:" 8 48 3>&1 1>&2 2>&3 3>&1)"
		pwconfirm="$(dialog --no-cancel --passwordbox "Retype your password:" 8 48 3>&1 1>&2 2>&3 3>&1)"
	done
	echo "$1:$pw" | chpasswd
	unset pw pwconfirm
}

mod_user() {
	usermod -aG wheel "$1" && mkdir -p "/home/$1" && chown -R "$1":wheel "/home/$1"
}

setup_user() {
	username="$(dialog --no-cancel --inputbox "Pick your username." 8 48 3>&1 1>&2 2>&3 3>&1)"
	while ! echo "$username" | grep -q "^[a-zA-Z_][a-zA-Z0-9_-]*$"; do
		username="$(dialog --no-cancel --inputbox "Chosen username is not valid. Try to use lower-case and upper-case letters, digits, underscore or hyphen." 12 64 3>&1 1>&2 2>&3 3>&1)"
	done
	check_user_existence "$username" && mod_user "$username" || add_user "$username" || return 1
}

switch_to_zsh() {
	chsh -s /bin/zsh "$username" >/dev/null 2>&1
	sudo -u "$username" mkdir -p "/home/$username/.cache/zsh"
}


pacman --noconfirm --needed -Sy dialog || exit_with_error "You must be connected to internet and run this script as root."
dialog --title "System rice installation" --yes-label "Start" --no-label "Cancel" --yesno "This script will rice your system. It should be executed on freshly installed base Artix linux system, otherwise something could go wrong (e.g. overwriting or corrupting important files)." 12 72 || exit_with_error "User exited."

dialog --title "Status" --infobox "Configuring pacman and installing some basic packages needed by this script. It might take a while." 8 64
enable_arch_repos
install_base
system_beep_off

setup_user || exit_with_error "User exited."

dialog --title "Status" --infobox "Getting ready for installing packages." 6 64
echo "%wheel ALL=(ALL) NOPASSWD: ALL #artir" >>/etc/sudoers
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
install_yay || 
	dialog --title "Installation error" --yes-label "Continue" --no-label "Abort" --yesno "Yay installation failed. Do you wish to continue?" 6 64 || 
	exit_with_error "User exited."
install_pkgs "$pkg_list"
install_dotfiles "$dotfiles_repo"
rm -f /home/$username/LICENSE /home/$username/README.md
sed -i "/#artir/d" /etc/sudoers
echo "%wheel ALL=(ALL) ALL" >>/etc/sudoers
#echo "%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot"

[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

switch_to_zsh

dialog --title "Installation complete" --msgbox "Installation was successful. You can now relogin as new user and execute startx to enjoy simple desktop experience." 8 64
clear

exit 0
