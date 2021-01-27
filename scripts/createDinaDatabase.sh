#!/bin/bash

# This script will only run if the database does NOT already exist

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"
dina_db_exists=`psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB -qt -c "SELECT 1 FROM pg_database WHERE datname = '$1'"`

if [ $dina_db_exists = "1" ]
then
  echo "DINA database $1 already exists. Skipping..."
else
  echo "Creating DINA database $1"
  psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB -c "CREATE DATABASE $1"

  echo "Change permissions on database $1"
  DINA_DB=$1 envsubst < db-init.sql.tmpl | psql -q -U $POSTGRES_USER -h $POSTGRES_HOST agent

  echo "Creating Schema $1 and database users"
  DINA_DB=$1 SCHEMA=$1 MIGRATION_USER_PW=$2 WEB_USER_PW=$3 envsubst < init-dina-module-db.sql.tmpl | psql -q -U $POSTGRES_USER -h $POSTGRES_HOST $1
fi
