# /etc/ssh/sshd_config.d/10-hardening.conf
# Plantilla: los marcadores @VARIABLE@ son sustituidos por setup-debian.sh
Port 22
Protocol 2
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication @SSH_PASSWORD_AUTH@
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowUsers @ADMIN_USER@
