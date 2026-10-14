#!/bin/bash
set -e

# Kreiraj grupu i usera vmail ako ne postoji
getent group vmail >/dev/null || groupadd -g 5000 vmail
id -u vmail >/dev/null 2>&1 || useradd -u 5000 -g 5000 -m -d /home/vmail -s /sbin/nologin vmail

# Kreiraj home root za admin01
mkdir -p /home/vmail
chown root:root /home/vmail
chmod 755 /home/vmail

# Stvori fajl sa porukom
echo "flag{admin_fell_for_the_nigerian_prince}

---

Dear Admin,  
I am a wealthy Nigerian Prince in desperate need of transferring 10,000,000 root privileges.  
All I require is your password and immediate execution of automat.sh.  
In return, you shall inherit eternal sudo rights.  

Sincerely,  
H.R.H. Prince of 10.11.1.6" > /root/flag.txt

# Postavi prava da samo root može čitati
chmod 600 /root/flag.txt


# Kreiraj admin01
id -u admin01 >/dev/null 2>&1 || useradd -u 5007 -g 5000 -m -d /home/vmail/admin01 -s /sbin/nologin admin01

# Folder za .sh fajlove
SH_DIR="/home/vmail/admin01/mail_sh"
mkdir -p "$SH_DIR"
chown root:root "$SH_DIR"
chmod 755 "$SH_DIR"

echo "Starting Python POP3 fetch script..."
python3 /usr/local/bin/pop3_fetch_sh.py &

echo "Mail retrieval finished. .sh attachments are in $SH_DIR"

# Drži container živim
tail -f /dev/null
