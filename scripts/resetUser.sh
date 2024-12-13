#!/bin/bash

# This script will reset a PostgreSQL user to use new credentials that are different from the ones in the dump file
# arguments: (1) user name, (2) user password

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"

user_count=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM pg_roles WHERE rolname = '$1'")

if [[ $user_count -eq 1 ]]; then
  psql -q -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "ALTER USER $1 WITH PASSWORD '$2'"
 
else
  echo "User $1 does not exist. Skipping..."
fi

