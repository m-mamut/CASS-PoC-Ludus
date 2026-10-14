#!/bin/bash
set -e

# Prepare LDAP DB
find /var/lib/ldap -type f ! -name 'DB_CONFIG' -delete
chown -R ldap:ldap /var/lib/ldap
chmod 700 /var/lib/ldap
chmod 600 /var/lib/ldap/DB_CONFIG

# Postavi limit za maksimalan broj otvorenih fajlova
ulimit -n 1024

# Start LDAP
echo "Starting OpenLDAP"
slapd -u ldap -g ldap -f /etc/openldap/slapd.conf -h "ldap://0.0.0.0:389" &

sleep 5

# Add initial LDAP entries
ldapadd -x -D "cn=admin,dc=tq,dc=dev" -w adminpassword -f /tmp/example.ldif || true


groupadd -g 5000 vmail
useradd -u 5000 -g 5000 -m -d /home/vmail -s /sbin/nologin vmail
mkdir -p /home/vmail
chown -R vmail:vmail /home/vmail



# Start rsyslog
echo "Starting rsyslog"
touch /var/log/maillog
chown root:root /var/log/maillog
chmod 640 /var/log/maillog

cat > /etc/rsyslog.d/10-mail.conf <<'EOF'
module(load="imuxsock")        # Omogućuje lokalni syslog socket
module(load="omstdout")        # Omogućuje slanje loga na stdout
mail.*    -/var/log/maillog
mail.*    :omstdout:
EOF

rsyslogd

# Postfix TLS & SASL konfiguracija iz starog
echo "Configuring Postfix TLS & SASL"
postconf -e "smtpd_tls_cert_file = /etc/pki/tls/certs/localhost.crt"
postconf -e "smtpd_tls_key_file = /etc/pki/tls/private/localhost.key"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_auth_only = no"
postconf -e "smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3"
postconf -e "smtpd_tls_mandatory_ciphers = medium"

chown root:postfix /etc/postfix/ldap-users.cf
chmod 640 /etc/postfix/ldap-users.cf

chmod 640 /etc/postfix/ldap-aliases.cf
chown root:postfix /etc/postfix/ldap-aliases.cf

postconf -e "syslog_facility = mail"
postconf -e "syslog_name = postfix"
chown postfix:postfix /var/spool/postfix/private
chmod 755 /var/spool/postfix/private

# Start Postfix
postfix start

# Prepare logs for dovecot
mkdir -p /var/log
touch /var/log/dovecot.log /var/log/dovecot-info.log
chown dovecot:dovecot /var/log/dovecot*.log
chmod 640 /var/log/dovecot*.log
usermod -aG mail dovecot

# Start Dovecot
echo "Starting Dovecot"
dovecot


echo "[*] Waiting 3s for services to settle..."
sleep 3

send_mail() {
    FROM="$1"
    TO="$2"
    SUBJECT="$3"
    BODY="$4"

    echo -e "Subject: $SUBJECT\nFrom: $FROM\nTo: $TO\n\n$BODY" \
    | sendmail -t "$TO"
    echo "[+] Mail sent: $FROM -> $TO ($SUBJECT)"
}

### === Fake normal mails ===

send_mail "newsletter@corp.com" "devjunior@tq.dev" \
"Weekly Tech Digest" \
"Hello Junior,\n\nHere is your weekly digest of technology news, updates, and articles we thought you might find useful. This week's edition covers best practices in microservices, upcoming changes in Python 3.13, and a guide to securing Docker containers in production. We also included a section on developer productivity tools that can help streamline your workflow.\n\nBest regards,\nTech Digest Team"

send_mail "updates@jira.tq.dev" "devsenior@tq.dev" \
"[JIRA] Ticket #1234 Updated" \
"Hi,\n\nThe issue regarding API timeout (Ticket #1234) has been updated by QA. They confirmed that the recent fix is stable under load tests. However, they noted a few edge cases that might still cause unexpected delays. Please review their comments in JIRA and let us know if additional adjustments are required before this can be marked as resolved.\n\nThanks,\nJIRA Notifications"

send_mail "ceooffice@tq.dev" "ceo@tq.dev" \
"Meeting Reminder" \
"Dear CEO,\n\nThis is a reminder about tomorrow’s board meeting scheduled at 09:00 in the main conference room. The agenda includes the quarterly financial report, updates on the new product launch, and discussions around upcoming regulatory changes. Please review the attached briefing documents before the meeting so we can use the time effectively.\n\nSincerely,\nExecutive Office"

send_mail "hr@tq.dev" "admin01@tq.dev" \
"Policy Update" \
"Dear Colleague,\n\nWe would like to inform you about the new IT security policy that becomes effective next week. This update introduces stricter requirements for password complexity, mandatory use of VPN when working remotely, and a new incident reporting procedure. Please read the full document attached as PDF and acknowledge receipt in the HR portal.\n\nThank you,\nHR Department"

### === The important malicious mail ===
send_mail "admin01@tq.dev" "devsenior@tq.dev" \
"URGENT: Need script for LDAP automation" \
"Hello,\n\nI know you're on your well-deserved vacation, but I just got a direct request from the CEO — he needs us to speed up the onboarding of several new employees today. He specifically asked if we could automate the process of creating LDAP accounts instead of doing it manually.\n\nCould you please send me the current automat.sh script for LDAP via email as soon as possible? It's quite urgent.\n\nThanks so much!"

### More noise
send_mail "marketing@corp.com" "ceo@tq.dev" \
"Monthly Performance Report" \
"Dear CEO,\n\nAttached you will find the monthly marketing performance report. It includes campaign performance metrics, customer acquisition data, and an overview of our latest digital initiatives. We also prepared insights into social media engagement trends and recommendations for Q4 budget allocation.\n\nBest regards,\nMarketing Department"

send_mail "colleague@corp.com" "devjunior@tq.dev" \
"Lunch?" \
"Hey,\n\nI was thinking of grabbing lunch around 12:30 today at the cafeteria. Would you like to join? It’s been a while since we caught up, and I’d like to hear how your current project is going.\n\nCheers,\nYour Colleague"


# Keep container running and show maillog live for debugging
tail -f /var/log/maillog
