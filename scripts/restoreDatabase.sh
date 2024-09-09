#!/bin/bash

# This script will restore a PostgreSQL database from a dump file
# arguments: (1) database name, (2) database user, (3) database password, (4) path to pg_dump file

set +e

POSTGRES_DB=$1
DB_USER=$2
DB_PASSWORD=$3
PG_DUMP_PATH=$4
DECODED_DUMP_PATH="/tmp/decoded_dump.tar"

export PGPASSWORD="$DB_PASSWORD"


# Print the file path for debugging
echo "Encoded dump file path: '$PG_DUMP_PATH'"

# Check if the ENCODED_DUMP_PATH variable is set
if [ -z "$PG_DUMP_PATH" ]; then
  echo "Error: PG_DUMP_PATH is not set. Exiting..."
  exit 1
fi

# Decode the base64-encoded tar file
if [ -f "$PG_DUMP_PATH" ]; then
  echo "Decoding the base64-encoded tar file..."
  base64 -d "$PG_DUMP_PATH" > "$DECODED_DUMP_PATH"
else
  echo "Encoded dump file does not exist at path: '$PG_DUMP_PATH'"
  exit 1
fi

# Check if the decoded file is not empty
if [ ! -s "$DECODED_DUMP_PATH" ]; then
  echo "Decoded file is empty or does not exist. Exiting..."
  exit 1
fi

# Restore the database from the dump file with --clean option
echo "Restoring database $POSTGRES_DB from $DECODED_DUMP_PATH with --clean option"
pg_restore --clean -U "$DB_USER" -h $POSTGRES_HOST -d "$POSTGRES_DB" "$DECODED_DUMP_PATH"

echo "Database $POSTGRES_DB restored successfully."
