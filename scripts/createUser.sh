#!/bin/bash

# This script will only run if the user does NOT already exist
# arguments: (1) database name, (2) user name, (3) user password

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"

user_exists=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "SELECT 1 FROM pg_roles WHERE rolname = '$2'")

if [ "$user_exists" = "1" ]; then
  echo "User $1 already exists. Skipping..."
else
  echo "Creating user $1"
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "CREATE USER $2 NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT"

  psql -q -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "ALTER USER $2 WITH PASSWORD '$3'"

  echo "Grant connect to user $2 on database $1"
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "GRANT CONNECT ON DATABASE $1 TO $2;"
fi
