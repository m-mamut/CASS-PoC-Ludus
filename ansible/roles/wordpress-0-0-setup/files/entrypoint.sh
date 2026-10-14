#!/bin/bash
set -e

# Start MariaDB in the background
mysqld_safe --user=mysql &
sleep 5


mkdir -p /var/www/secrets
echo -e "postmaster\nsupersecret" > /var/www/secrets/mail_creds.txt
chown -R apache:apache /var/www/secrets
chmod 750 /var/www/secrets
chmod 640 /var/www/secrets/mail_creds.txt

mkdir -p /run/php-fpm
chown apache:apache /run/php-fpm
php-fpm -D

# Start Apache in the foreground
exec /usr/sbin/httpd -D FOREGROUND
