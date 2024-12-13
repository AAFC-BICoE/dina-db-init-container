#!/bin/bash

# This script will restore a PostgreSQL database from a dump file
# arguments: (1) database name, (2) database user, (3) database password, (4) path to pg_dump file

set +e

DB_DUMP_FILE_PATH=$1
DECODED_DUMP_PATH="/tmp/decoded_dump.sql"

export PGPASSWORD="$POSTGRES_PASSWORD"

# Print the input arguments for debugging
echo "Database Name: $POSTGRES_DB"
echo "Database User: $POSTGRES_USER"
echo "Encoded dump file path: '$DB_DUMP_FILE_PATH'"
echo "PostgreSQL Host: $POSTGRES_HOST"

# Check if the DB_DUMP_FILE_PATH variable is set
if [ -z "$DB_DUMP_FILE_PATH" ]; then
  echo "Error: DB_DUMP_FILE_PATH is not set. Exiting..."
  exit 1
fi

# Decode the base64-encoded sql file
if [ -f "$DB_DUMP_FILE_PATH" ]; then
  echo "Decoding the base64-encoded sql file..."
  base64 -d "$DB_DUMP_FILE_PATH" > "$DECODED_DUMP_PATH"
else
  echo "Encoded dump file does not exist at path: '$DB_DUMP_FILE_PATH'"
  exit 1
fi

# Check if the decoded file is not empty
if [ ! -s "$DECODED_DUMP_PATH" ]; then
  echo "Decoded file is empty or does not exist. Exiting..."
  exit 1
fi

# Print the decoded file path for debugging
echo "Decoded dump file path: '$DECODED_DUMP_PATH'"

# Remove $POSTGRES_USER SQL commands from the decoded dump file.
sed -i "/^\(DROP\|CREATE\|ALTER\) ROLE $POSTGRES_USER.*;/d" $DECODED_DUMP_PATH
echo "Removed '$POSTGRES_USER' SQL commands from the dump."

# Check if PostgreSQL server is running
echo "Checking PostgreSQL server connection..."
pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER
if [ $? -ne 0 ]; then
  echo "PostgreSQL server is not running or not accessible. Exiting..."
  exit 1
fi

# Restore the database from the dump file
echo "Restoring database $POSTGRES_DB from $DECODED_DUMP_PATH"
psql -h $POSTGRES_HOST -f "$DECODED_DUMP_PATH" -U $POSTGRES_USER $POSTGRES_DB

if [ $? -eq 0 ]; then
    echo "Database $POSTGRES_DB restored successfully."
else
    echo "Database restoration failed."
fi
