# Author: Roy Wiseman 2025-02
####################
# Display login banner, except for when starting a new tmux session)
#################### 

RGB() { awk 'BEGIN{ s="          "; s=s s s s s s s s; for (colnum = 0; colnum<77; colnum++) { r = 255-(colnum*255/76); g = (colnum*510/76); b = (colnum*255/76); if (g>255) g = 510-g; printf "\033[48;2;%d;%d;%dm", r,g,b; printf "\033[38;2;%d;%d;%dm", 255-r,255-g,255-b; printf "%s\033[0m", substr(s,colnum+1,1); } printf "\n";}'; }
ver() { local RELEASE; if [ -f /etc/os-release ]; then . /etc/os-release; RELEASE="${PRETTY_NAME:-$NAME}"; elif [ -f /etc/redhat-release ]; then RELEASE=$(cat /etc/redhat-release); elif [ -f /etc/lsb-release ]; then RELEASE=$(grep -E '^(DISTRIB_DESCRIPTION|DESCRIPTION)=' /etc/lsb-release | head -n1 | cut -d'=' -f2- | sed 's/"//g'); elif [ -f /etc/debian_version ]; then RELEASE="Debian $(cat /etc/debian_version)"; elif [ -f /etc/alpine-release ]; then RELEASE="Alpine $(cat /etc/alpine-release)"; fi; printf "${RELEASE:-Unknown Distro}, $(uname -msr)\n"; }
upnow() { uptime | awk '{sub(/^.*up /, "up "); sub(/,[ \t]*[0-9]+ user.*/,""); print}'; }
sys() { awk -F": " '/^model name/ { mod=$2 } /^cpu MHz/ { mhz=$2 } /^cpu core/ {core=$2} /^flags/ { virt="No Virtualisation";match($0,"svm");if (RSTART!=0) { virt="SVM-Virtualisation" };match($0,"vmx");if (RSTART!=0) { virt="VMX-Virtualisation" } } /^Mem:/ {split($2,arr," ");tot=arr[1];free=arr[2]} END { printf "%s, %dMHz, %s core(s), %s, %sB Memory (%sB Used)\n",mod,mhz,core,virt,tot,free }' /proc/cpuinfo <(free -mh); printf "$(hostname -I)\n"; }   # Good sed tutorial https://linuxhint.com/newline_replace_sed/
fignow() { printf "\e[33m$(figlet -w -t -f /usr/share/figlet/small.flf $(date +"%a, %d %b, wk%V"))"; [ -f /usr/share/figlet/univers.flf ] && local opts="-f /usr/share/figlet/univers.flf" || local opts="-f /usr/share/figlet/big.flf"; printf "\n\e[94m$(figlet -t $opts $(date +"%H:%M"))\e[00m\n"; }   # date "%b %d, week %V", was larry3d.flf
figclock() { while [ 1 ]; do clear; printf "\e[33m"; df -kh 2> /dev/null; printf "\e[31m\n"; top -n 1 -b | head -11; printf "\e[33m$(figlet -w -t -f small $(date +"%b %d, week %V"))\n"; font=`figrandom`; printf "$(echo $font)\n\e[94m$(figlet -w -t -f $font $(date +"%H:%M:%S"))\e[00m\n"; printf "\e[35m5 second intervals, Ctrl-C to quit.\e[00m"; sleep 3; done; }
login_banner() { printf "\n$(RGB)\n$(ver) : $(upnow) : $(date +"%Y-%m-%d, %H:%M:%S, %A, Week %V")\n$(sys)\n"; type figlet >/dev/null 2>&1 && fignow; }

[ -z "$TMUX" ] && login_banner   # Only display login_banner if this is not a new tmux session
# [ -z "$TMUX" ] && export TERM=xterm-256color && exec tmux   # Optional: Always start tmux at login, but skip when running a new tmux session
# read -p "Run tmux? (y/n)" -n 1 -r echo if [[ $REPLY =~ ^[Yy]$ ]]; then exec tmux new-session -A -s main fi fi
# Offer to start tmux, https://unix.stackexchange.com/questions/43601/how-can-i-set-my-default-shell-to-start-up-tmux






####################
# Other fig-cow-pony-toilet stuff from .custom

# type figlet  &> /dev/null && fignow() { printf "\e[33m$(figlet -w -t -f /usr/share/figlet/small.flf $(date +"%a, %d %b, wk%V"))"; [ -f /usr/share/figlet/univers.flf ] && local opts="-f /usr/share/figlet/univers.flf" || local opts="-f /usr/share/figlet/big.flf"; printf "\n\e[94m$(figlet -t $opts $(date +"%H:%M"))\e[00m\n"; }   # date "%b %d, week %V", was larry3d.flf
# type figlet  &> /dev/null && figclock() { while [ 1 ]; do clear; printf "\e[33m"; df -kh 2> /dev/null; printf "\e[31m\n"; top -n 1 -b | head -11; printf "\e[33m$(figlet -w -t -f small $(date +"%b %d, week %V"))\n"; font=`figrandom`; printf "$(echo $font)\n\e[94m$(figlet -w -t -f $font $(date +"%H:%M:%S"))\e[00m\n"; printf "\e[35m5 second intervals, Ctrl-C to quit.\e[00m"; sleep 3; done; } # 2> /dev/null suppresses errors from smb shares
# type cowsay  &> /dev/null && cowrandom() { if [ -d /usr/share/cowsay/cows/ ]; then files=/usr/share/cowsay/cows/*; else files=/usr/share/cowsay/*; fi; printf "%s\n" "${files[RANDOM % ${#files}]}"; }
# type cowsay  &> /dev/null && cowall() { if [ -d /usr/share/cowsay/cows/ ]; then files=/usr/share/cowsay/cows/*.cow; else files=/usr/share/cowsay/*.cow; fi; echo $files; for f in $files; do printf "\n\n\n\n\n$f\n\n"; fortune | cowsay -f $f; done; }   # https://stackoverflow.com/questions/12320521/simple-bash-for-f-in#12320617
# type cowsay  &> /dev/null && alias fcow="fortune | cowsay -f $(cowrandom)"   # -b Borg, -d dead, -g greedy, -p paranoia, -s stoned, -t tired, -w wired mode, -y youthful
# type cowsay  &> /dev/null && cowmix() { if [ -d /usr/share/cowsay/cows/ ]; then files=(/usr/share/cowsay/cows/*.cow); else files=(/usr/share/cowsay/*.cow); fi; while IFS= read -d $'\0' -r file; do fortune | cowsay -f "$file"; echo -e "$file\n"; sleep 3; done < <(printf '%s\0' "${files[@]}" | shuf -z); }
# type ponysay &> /dev/null && ponyrandom() { if [ -d /usr/share/ponysay/ponies/ ]; then files=/usr/share/ponysay/ponies/*; else files=/usr/share/ponysay/*; fi; printf "%s\n" "${files[RANDOM % ${#files}]}"; }
# type ponysay &> /dev/null && ponyall() { if [ -d /usr/share/ponysay/ponies/ ]; then files=/usr/share/ponysay/ponies/*.pony; else files=/usr/share/ponysay/*.pony; fi; echo $files; for f in $files; do printf "\n\n\n\n\n$f\n\n"; fortune | ponysay -f $f; sleep 2; done; }   # https://stackoverflow.com/questions/12320521/simple-bash-for-f-in#12320617
# type ponysay &> /dev/null && alias fpony="fortune | ponysay -f $(ponyrandom)"
# type ponysay &> /dev/null && ponymix() { files=(/usr/share/ponysay/ponies/*.pony); while IFS= read -d $'\0' -r file; do fortune | ponysay -f "$file" -b round 2> /dev/null; echo -e "$file\n"; sleep 3; done < <(printf '%s\0' "${files[@]}" | shuf -z); }
# type toilet  &> /dev/null && toiletgayclock() { echo "$(date '+%D %T' | toilet -f `figrandom` -F border --gay)"; }
