#!/bin/bash

# This script will only run if the database does NOT already exist
# arguments: (1) database name

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"

dina_db_exists=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "SELECT 1 FROM pg_database WHERE datname = '$1'")

if [ "$dina_db_exists" = "1" ]; then
  echo "DINA database $1 already exists. Skipping..."
else
  echo "Creating database $1"
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$POSTGRES_DB" -qt -c "CREATE DATABASE $1"

  echo "Changing default permissions on database $1"
  DINA_DB=$1 envsubst < db-init.sql.tmpl | psql -q -U "$POSTGRES_USER" -h "$POSTGRES_HOST" "$1"
fi
