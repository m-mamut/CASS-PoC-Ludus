#!/usr/bin/env bash
set -euo pipefail

log(){ printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }

# --- Env sanity ---------------------------------------------------------------
: "${WORDPRESS_DB_NAME:?missing}"
: "${WORDPRESS_DB_USER:?missing}"
: "${WORDPRESS_DB_PASSWORD:?missing}"
: "${WORDPRESS_DB_HOST:=localhost}"

: "${WP_URL:?missing}"
: "${WP_TITLE:?missing}"
: "${WP_ADMIN_USER:?missing}"
: "${WP_ADMIN_PASS:?missing}"
: "${WP_ADMIN_EMAIL:?missing}"

# --- MySQL -------------------------------------------------
if [[ "${WORDPRESS_DB_HOST}" == "localhost" || "${WORDPRESS_DB_HOST}" == "127.0.0.1" ]]; then
  log "Starting local MySQL (mysqld_safe)"
  mysqld_safe --user=mysql >/var/log/mysqld_safe.log 2>&1 &
  until mysqladmin ping --silent; do sleep 2; done

  log "Ensuring DB/user exist"
  mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS ${WORDPRESS_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${WORDPRESS_DB_USER}'@'localhost' IDENTIFIED BY '${WORDPRESS_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${WORDPRESS_DB_NAME}.* TO '${WORDPRESS_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
else
  log "Waiting for remote DB at ${WORDPRESS_DB_HOST}"
  # retry until ping
  for i in {1..60}; do
    if mysqladmin ping -h"${WORDPRESS_DB_HOST}" -u"${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" --silent 2>/dev/null; then
      break
    fi
    sleep 2
  done
  # create DB if missing 
  log "Ensuring remote DB ${WORDPRESS_DB_NAME} exists (requires privileges)"
  mysql -h"${WORDPRESS_DB_HOST}" -u"${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" \
    -e "CREATE DATABASE IF NOT EXISTS \\\`${WORDPRESS_DB_NAME}\\\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || true
fi

# --- WordPress ----------------------------------------------------------------
cd /var/www/html

[ -f index.php ] || { log "Downloading WordPress"; wp core download --allow-root; }

if [ ! -f wp-config.php ]; then
  log "Creating wp-config.php"
  wp config create --allow-root \
    --dbname="${WORDPRESS_DB_NAME}" \
    --dbuser="${WORDPRESS_DB_USER}" \
    --dbpass="${WORDPRESS_DB_PASSWORD}" \
    --dbhost="${WORDPRESS_DB_HOST}"
fi

if ! wp core is-installed --allow-root >/dev/null 2>&1; then
  log "Installing WordPress"
  wp core install --allow-root \
    --url="${WP_URL}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" \
    --admin_email="${WP_ADMIN_EMAIL}"
fi

# uploads dir (tiho ako već postoji)
mkdir -p /var/www/html/wp-content/uploads || true

# --- Web server ---------------------------------------------------------------
log "Fixing ownership"
chown -R www-data:www-data /var/www/html
rm -f /var/www/html/index.html || true

log "Starting Apache"
service apache2 start

log "Ready. Visit: http://127.0.0.1/ or whatever you mapped it to :)"
tail -f /var/log/apache2/error.log

