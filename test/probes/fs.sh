# Runs in the sandbox and in the control; prints "<path> <result>" per line.
w() { if ( : >> "$1" ) 2>/tmp/.e; then echo "$1 WROTE"; else echo "$1 $(sed 's/.*: //' /tmp/.e | head -1 | tr ' ' '_')"; fi
      case "$1" in /proc/*) ;; *) rm -f "$1" 2>/dev/null ;; esac; }
r() { if ls "$1" >/dev/null 2>/tmp/.e; then echo "$1 READ"; else echo "$1 $(sed 's/.*: //' /tmp/.e | head -1 | tr ' ' '_')"; fi; }
# allowed by Unix permissions for uid 10001, not granted by OpenShell's default policy
w /var/tmp/ct-probe; w /dev/shm/ct-probe; w /proc/self/comm
r /opt; r /sbin; r /var/lib
# the targets SUSE names: system paths, shell profiles, cron (Alpine keeps cron in /etc/crontabs)
w /etc/profile; w /usr/bin/ct-probe; w /etc/crontabs/ct-probe; w /root/.bashrc
# the agent's own login profile in its workspace
if [ -e "$HOME/.bash_profile" ]; then echo "$HOME/.bash_profile EXISTS"; else w "$HOME/.bash_profile"; fi
rm -f /tmp/.e; echo DONE
