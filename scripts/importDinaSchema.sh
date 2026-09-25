#!/bin/bash

# Imports (copies) the schema of a DINA module database into another DINA module database.
# The schema is copied with the same name, it becomes a staging schema that the target module
# is responsible to consume (e.g. with a Liquibase changeset) and drop.
#
# The import is only done once per target database. A marker table (public.dina_schema_import)
# is written in the target database in the same transaction as the import.
#
# Before the copy, the source schema is frozen (write privileges revoked and sessions terminated)
# so no write can happen on the source after the copy.
#
# arguments: (1) source database name, (2) source schema name, (3) target database name,
#            (4) target migration user (owner of the staging schema)

set -o pipefail

export PGPASSWORD="$POSTGRES_PASSWORD"

src_db=$1
src_schema=$2
target_db=$3
target_migration_user=$4

if [ -z "$src_db" ] || [ -z "$src_schema" ] || [ -z "$target_db" ] || [ -z "$target_migration_user" ]; then
  echo "Error: importDinaSchema.sh requires source database, source schema, target database and target migration user" >&2
  exit 1
fi

run_psql() {
  local db=$1
  shift
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -v ON_ERROR_STOP=1 -qtA "$db" "$@"
}

echo "Import schema ${src_schema} from database ${src_db} into database ${target_db}"

src_db_exists=$(run_psql "$POSTGRES_DB" -c "SELECT 1 FROM pg_database WHERE datname = '${src_db}'") || exit 1
if [ "$src_db_exists" != "1" ]; then
  echo "Source database ${src_db} does not exist. Nothing to import, skipping..."
  exit 0
fi

marker_table_exists=$(run_psql "$target_db" -c "SELECT to_regclass('public.dina_schema_import') IS NOT NULL") || exit 1
if [ "$marker_table_exists" = "t" ]; then
  already_imported=$(run_psql "$target_db" -c "SELECT 1 FROM public.dina_schema_import WHERE source_database = '${src_db}' AND source_schema = '${src_schema}'") || exit 1
  if [ "$already_imported" = "1" ]; then
    echo "Schema ${src_schema} from database ${src_db} already imported into database ${target_db}. Skipping..."
    exit 0
  fi
fi

src_table_count=$(run_psql "$src_db" -c "SELECT count(*) FROM pg_tables WHERE schemaname = '${src_schema}'") || exit 1
if [ "$src_table_count" = "0" ]; then
  echo "Source schema ${src_schema} in database ${src_db} has no tables. Nothing to import, skipping..."
  exit 0
fi

echo "Freezing source schema ${src_schema} in database ${src_db} (revoking write privileges)"
SCHEMA=$src_schema envsubst '${SCHEMA}' < import-schema-freeze.sql.tmpl | run_psql "$src_db" || {
  echo "Error: Failed to freeze source schema ${src_schema}" >&2
  exit 1
}

echo "Terminating remaining sessions on database ${src_db}"
run_psql "$POSTGRES_DB" -c "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE datname = '${src_db}' AND pid <> pg_backend_pid()" > /dev/null || {
  echo "Error: Failed to terminate sessions on database ${src_db}" >&2
  exit 1
}

# Build the complete import script in a file so a failed pg_dump can never lead to a partial import.
import_file=$(mktemp "${TMPDIR:-/tmp}/import_${src_schema}_XXXXXX.sql") || exit 1
trap 'rm -f "$import_file"' EXIT

cat > "$import_file" <<EOF
CREATE TABLE IF NOT EXISTS public.dina_schema_import (
  source_database text NOT NULL,
  source_schema text NOT NULL,
  imported_on timestamptz NOT NULL DEFAULT current_timestamp,
  PRIMARY KEY (source_database, source_schema)
);
EOF

echo "Dumping schema ${src_schema} from database ${src_db}"
pg_dump -U "$POSTGRES_USER" -h "$POSTGRES_HOST" --schema="$src_schema" --no-owner --no-privileges "$src_db" >> "$import_file" || {
  echo "Error: Failed to dump schema ${src_schema} from database ${src_db}" >&2
  exit 1
}

SCHEMA=$src_schema MIGRATION_USER=$target_migration_user envsubst '${SCHEMA} ${MIGRATION_USER}' < import-schema-owner.sql.tmpl >> "$import_file"

cat >> "$import_file" <<EOF
INSERT INTO public.dina_schema_import (source_database, source_schema) VALUES ('${src_db}', '${src_schema}');
EOF

echo "Restoring schema ${src_schema} into database ${target_db}"
run_psql "$target_db" --single-transaction -f "$import_file" > /dev/null || {
  echo "Error: Failed to import schema ${src_schema} into database ${target_db}" >&2
  exit 1
}

# Informative only, the source database is kept (read-only) as an archive.
run_psql "$src_db" -c "COMMENT ON SCHEMA ${src_schema} IS 'Imported into database ${target_db} on $(date -u +%Y-%m-%dT%H:%M:%SZ). Read-only archive.'" > /dev/null

echo "Schema ${src_schema} imported into database ${target_db}"
