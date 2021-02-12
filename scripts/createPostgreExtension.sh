#!/bin/bash

# arguments: (1)extension name, (2)database name, (3) schema name

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"

echo "Creating Postgres Extension $1 on Datbase $2 and Schema $3"
psql -U $POSTGRES_USER -h $POSTGRES_HOST $2 -qt -c "CREATE EXTENSION IF NOT EXISTS $1 SCHEMA $3"


