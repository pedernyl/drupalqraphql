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

#Fetching args for sitename, user and pass
#Defaultvalues
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

docker compose build --no-cache

# Start Docker containers in the background
echo "Starting Docker containers..."
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
until docker exec "$DRUPAL_CONTAINER" drush status >/dev/null 2>&1; do
  echo "Drupal not ready yet. Retrying in 3 seconds..."
  sleep 3
done
echo "Drupal container is ready!"