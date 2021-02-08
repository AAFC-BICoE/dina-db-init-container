#!/bin/bash

# This script will only run if the database does NOT already exist
# arguments: (1)database name, (2) schema name, (3)migration user name, (4)migration user passord, (5)web user name, (6)webuser passpord

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"

dina_db_exists=`psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB -qt -c "SELECT 1 FROM pg_database WHERE datname = '$1'"`

if [ "$dina_db_exists" = "1" ]; then
  echo "DINA database $1 already exists. Skipping..."
else
  echo "Creating DINA database $1"
  psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB -qt -c "CREATE DATABASE $1"

  echo "Change permissions on database $1"
  DINA_DB=$1 envsubst < db-init.sql.tmpl | psql -q -U $POSTGRES_USER -h $POSTGRES_HOST $1

  echo "Creating Schema $2 and database users $3 and $5"
  DINA_DB=$1 SCHEMA=$2 MIGRATION_USER=$3 MIGRATION_USER_PW=$4 WEB_USER=$5 WEB_USER_PW=$6 envsubst < init-dina-module-db.sql.tmpl | psql -q -U $POSTGRES_USER -h $POSTGRES_HOST $1
fi
