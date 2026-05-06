#!/bin/bash

# This script will only run if the user does NOT already exist
# arguments: (1) database name, (2) user name, (3) user password

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"

user_exists=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt \
  -c "SELECT 1 FROM pg_roles WHERE rolname = '$2'")

if [ "$user_exists" = "1" ]; then
  echo "User $2 already exists. Skipping..."
else
  echo "Creating user $2"
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt \
    -c "CREATE USER $2 NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT"

  user_name="$2"
  user_password="$3"

  # Escape single quotes for SQL
  escaped_pw=$(printf "%s" "$user_password" | sed "s/'/''/g")

  # Disable command echoing and save previous xtrace state
  case $- in
    *x*) had_xtrace=1 ;;
    *)   had_xtrace= ;;
  esac
  set +x

  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" \
    -qt -c "ALTER USER \"$user_name\" WITH PASSWORD E'$escaped_pw';" || {
      echo "Error: Failed to set password for user '$user_name'" >&2
      exit 1
    }

  # Re-enable command echoing with previous settings.
  [[ -n $had_xtrace ]] && set -x

  echo "Grant connect to user $2 on database $1"
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt \
    -c "GRANT CONNECT ON DATABASE $1 TO $2;"
fi
