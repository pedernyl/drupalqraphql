#!/bin/bash

# This script installs the required packages for the project
# and sets up the environment.

# Get the name of the Drupal container dynamically from docker-compose.yml
DRUPAL_CONTAINER_NAME=$(docker-compose config | awk '
  BEGIN {found = 0}
  /services:/ {found = 1}
  found && /drupal:/ {getline; while ($1 != "container_name:") {getline}; print $2; exit}
')

# Check if the container name was found
if [ -z "$DRUPAL_CONTAINER_NAME" ]; then
  DRUPAL_CONTAINER_NAME="drupal"
fi

# Print the container name
echo "Drupal container name: $DRUPAL_CONTAINER_NAME"

# Get the name of the database container dynamically from docker-compose.yml
DB_CONTAINER_NAME=$(docker-compose config | awk '
  BEGIN {found = 0}
  /services:/ {found = 1}
  found && /mariadb:/ {getline; while ($1 != "container_name:") {getline}; print $2; exit}
')

# Check if the database container name was found
if [ -z "$DB_CONTAINER_NAME" ]; then
  DB_CONTAINER_NAME="mariadb"
fi

# Print the database container name
echo "Database container name: $DB_CONTAINER_NAME"

# Fetching args for sitename, user and pass
# Default values
sitename="drupal"
username="drupal"
password="drupal"

print_help() {
    echo "Usage: $0 [--sitename|-s <name>] [--user|-u <user>] [--pass|-p <password>]"
    echo
    echo "Flags:"
    echo "  --sitename, -s     Sitename"
    echo "  --user, -u         Username"
    echo "  --pass, -p         Password"
    echo "  --help             Show this help"
}

# Read args
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -s|--sitename)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                sitename="$2"
                shift
            else
                echo "⚠️  Error: --sitename requires a value."
                exit 1
            fi
            ;;
        -u|--user)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                username="$2"
                shift
            else
                echo "⚠️  Error: --user requires a value."
                exit 1
            fi
            ;;
        -p|--pass)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                password="$2"
                shift
            else
                echo "⚠️  Error: --pass requires a value."
                exit 1
            fi
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "⚠️  Unknown flag:: $1"
            print_help
            exit 1
            ;;
    esac
    shift
done

# Check if the containers are already running
if [ "$(docker ps -q -f name="$DRUPAL_CONTAINER_NAME")" ] && [ "$(docker ps -q -f name="$DB_CONTAINER_NAME")" ]; then
    echo "Containers are already running. Exiting script."
    exit 0
fi

# Check if the containers already exist but are not running
if [ "$(docker ps -a -q -f name="$DRUPAL_CONTAINER_NAME")" ] || [ "$(docker ps -a -q -f name="$DB_CONTAINER_NAME")" ]; then
    echo "Containers exist but are not running. Starting them..."
    docker compose up -d
    echo "Containers started. Exiting script."
    exit 0
fi

echo "Building and starting the containers..."
docker compose build
docker compose up -d

# Wait for the database container to become ready
echo "Waiting for the database to be ready..."
until docker exec "$DB_CONTAINER_NAME" mariadb -h "localhost" -u root -p'rootpassword' -e "SELECT 1" >/dev/null 2>&1; do
    echo "Database not ready yet. Retrying in 3 seconds..."
    sleep 3
done
echo "Database is ready!"

# Wait for the Drupal container to be ready to accept Drush commands
echo "Waiting for the Drupal container to be ready..."
until docker exec "$DRUPAL_CONTAINER_NAME" drush core-status >/dev/null 2>&1; do
  echo "Drupal not ready yet. Retrying in 3 seconds..."
  sleep 3
done
echo "Drupal container is ready!"

echo "Preparing file system and installing Drupal..."

echo "Getting Drupal root path..."
DRUPAL_ROOT=$(docker exec "$DRUPAL_CONTAINER_NAME" drush core-status | grep "Drupal root" | awk -F': ' '{print $2}' | xargs | tr -d '\r')
echo "Drupal root is: $DRUPAL_ROOT"

# Exit if root path couldn't be determined
if [ -z "$DRUPAL_ROOT" ]; then
  echo "❌ Failed to detect Drupal root path. Aborting script."
  exit 1
fi

echo "Detecting web server user inside the container..."
APACHE_USER=$(docker exec "$DRUPAL_CONTAINER_NAME" ps aux | grep -E 'apache2|httpd|php-fpm' | grep -v root | awk '{print $1}' | head -n 1)
echo "Detected web server user: $APACHE_USER"

if [ -z "$APACHE_USER" ]; then
  echo "❌ Failed to detect web server user. Aborting script."
  exit 1
fi

echo "Setting correct file permissions for Drupal..."
docker exec "$DRUPAL_CONTAINER_NAME" chmod -R ug+w "$DRUPAL_ROOT/sites/default"
docker exec "$DRUPAL_CONTAINER_NAME" mkdir -p "$DRUPAL_ROOT/sites/default/files"
docker exec "$DRUPAL_CONTAINER_NAME" chmod -R ug+w "$DRUPAL_ROOT/sites/default/files"
docker exec "$DRUPAL_CONTAINER_NAME" chown -R "$APACHE_USER:$APACHE_USER" "$DRUPAL_ROOT/sites/default"
echo "✅ Permissions and ownership set!"

docker exec "$DRUPAL_CONTAINER_NAME" drush site-install standard \
--site-name="$sitename" \
--account-name="$username" \
--account-pass="$password" \
--db-url="mysql://drupal:drupal@$DB_CONTAINER_NAME/drupal" \
-y

echo "🔒 Configuring trusted_host_patterns in settings.php..."
echo "🔒 Writing correct trusted_host_patterns block directly with PHP..."

docker exec "$DRUPAL_CONTAINER_NAME" php -r '
  $file = "/var/www/html/sites/default/settings.php";
  $code = "\n\$settings[\"trusted_host_patterns\"] = [\n  \"^localhost$\",\n  \"^127\\.0\\.0\\.1$\",\n];\n";
  $existing = file_get_contents($file);
  // Remove previous blocks (if any)
  $existing = preg_replace("/\\\$settings\\[\"trusted_host_patterns\"\\]\s*\=\s*\[[^\]]*\];/s", "", $existing);
  file_put_contents($file, $existing . $code);
'

echo "Enabling GraphQL, GraphQL_compose and GraphQL_compose_views modules..."
docker exec "$DRUPAL_CONTAINER_NAME" drush en graphql graphql_compose graphql_compose_views -y

echo "Drupal installation and GraphQL activation completed!"

echo "Checking for updates"
docker exec "$DRUPAL_CONTAINER_NAME" drush cron