#! /bin/bash

./waitForDatabase.sh

export PGPASSWORD="$POSTGRES_PASSWORD"
psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB -c "CREATE DATABASE agent"
DINA_DB=agent envsubst < db-init.sql.tmpl | psql -U $POSTGRES_USER -h $POSTGRES_HOST agent
# DINA_DB=agent SCHEMA=agent MIGRATION_USER_PW=123 WEB_USER_PW=123 envsubst < init-dina-module-db.sql.tmpl | psql -U $POSTGRES_USER -h $POSTGRES_HOST -d $POSTGRES_DB

