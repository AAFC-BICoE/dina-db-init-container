#!/bin/bash

# Imports (copies) data from other DINA database(s) into a DINA database.
#
# The module declares what to import in <schema>.dina_data_import (pending rows have a null status) and creates
# the target tables (empty) with the same structure as the source tables.
# For each source database, the tables are exported in a single transaction, then imported (and marked as IMPORTED)
# in a single transaction, in the order of the dina_data_import ids (parent tables first). Data is copied as is (including ids)
# and the sequences of the target columns (serial/identity) are moved after the imported values.
# Imported source tables become owned by $POSTGRES_USER.
# If the source database doesn't exist, the rows are marked as SOURCE_NOT_FOUND.
# The source and target databases must both have a prefix or both have none (PREFIX_<source database> must then be
# set in this environment), otherwise the import is refused and the rows stay pending.
#
# arguments: (1) target database name, (2) target schema name

set -o pipefail

export PGPASSWORD="$POSTGRES_PASSWORD"

target_db=$1
target_schema=$2
data_import_table="${target_schema}.dina_data_import"

# Prefix of the target database (e.g. v0 for v0_collection), empty if none
target_prefix=""
[ "$target_db" != "$target_schema" ] && target_prefix=${target_db%_"${target_schema}"}

run_psql() {
  local db=$1
  shift
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -v ON_ERROR_STOP=1 -qtA "$db" "$@"
}

# Logs one line per row of the dina_data_import table, e.g. "#1 loan_transaction.transaction -> collection.transaction: pending"
log_data_imports() {
  run_psql "$target_db" -c "SELECT format('  #%s %s.%s -> ${target_schema}.%s%s: %s', id, source_schema, source_table, target_table,
      CASE WHEN source_database <> source_schema THEN ' (from database ' || quote_literal(source_database) || ')' ELSE '' END,
      CASE WHEN status IS NULL THEN 'pending'
           WHEN status = '' THEN 'status is an empty string, not pending (pending rows have a NULL status)'
           ELSE status || coalesce(' on ' || to_char(processed_on, 'YYYY-MM-DD HH24:MI:SS TZ'), '') END)
    FROM ${data_import_table} ORDER BY id"
}

# Nothing to import if the module didn't create the dina_data_import table
table_exists=$(run_psql "$target_db" -c "SELECT to_regclass('${data_import_table}') IS NOT NULL") || {
  echo "Error: could not check if ${data_import_table} exists in database ${target_db}" >&2
  exit 1
}
if [ "$table_exists" != "t" ]; then
  echo "Data import into ${target_db}: nothing to import (no ${data_import_table} table)"
  exit 0
fi

echo "Data import into ${target_db}:"
log_data_imports || exit 1

pending_sources=$(run_psql "$target_db" -F ' ' -c "SELECT DISTINCT source_database, source_schema FROM ${data_import_table} WHERE status IS NULL") || {
  echo "Error: could not read the pending data imports from ${data_import_table}" >&2
  exit 1
}
if [ -z "$pending_sources" ]; then
  echo "  Nothing to import (no pending row)"
  exit 0
fi

work_dir=$(mktemp -d) || exit 1
trap 'rm -rf "$work_dir"' EXIT

# For each source database with pending tables
while read -r src_base_db src_schema; do
  prefix_var="PREFIX_${src_base_db}"
  src_prefix=${!prefix_var}
  pending="source_database = '${src_base_db}' AND source_schema = '${src_schema}' AND status IS NULL"

  # Refuse to guess when only one of the source and target databases has a prefix
  if [ -n "$target_prefix" ] && [ -z "$src_prefix" ]; then
    echo "Error: database ${target_db} has the prefix ${target_prefix} but ${prefix_var} is not set, refusing to import from ${src_base_db}." \
      "Set ${prefix_var} in the environment of this init-db (see Data import in the README)" >&2
    exit 1
  fi
  if [ -z "$target_prefix" ] && [ -n "$src_prefix" ]; then
    echo "Error: ${prefix_var} is set (${src_prefix}) but database ${target_db} has no prefix, refusing to import from ${src_prefix}_${src_base_db}" >&2
    exit 1
  fi

  src_db=${src_base_db}
  prefix_info="no prefix"
  if [ -n "$src_prefix" ]; then
    src_db=${src_prefix}_${src_base_db}
    prefix_info="${prefix_var}=${src_prefix}"
  fi

  src_exists=$(run_psql "$POSTGRES_DB" -c "SELECT 1 FROM pg_database WHERE datname = '${src_db}'") || {
    echo "Error: could not check if database ${src_db} exists" >&2
    exit 1
  }
  if [ "$src_exists" != "1" ]; then
    echo "  Database ${src_db} (${prefix_info}) not found, marking as SOURCE_NOT_FOUND"
    run_psql "$target_db" -c "UPDATE ${data_import_table} SET status = 'SOURCE_NOT_FOUND', processed_on = now() WHERE ${pending}" || exit 1
    continue
  fi

  pending_tables=$(run_psql "$target_db" -c "SELECT id, source_table, target_table FROM ${data_import_table} WHERE ${pending} ORDER BY id") || {
    echo "Error: could not read the pending tables of ${src_base_db} from ${data_import_table}" >&2
    exit 1
  }
  # e.g. a source_database edited with an extra space: found by the loop but not matched exactly by the query
  if [ -z "$pending_tables" ]; then
    echo "Error: no pending row has exactly source_database = '${src_base_db}' and source_schema = '${src_schema}'" \
      "(check for extra spaces), refusing to import" >&2
    exit 1
  fi

  echo "  Importing from database ${src_db} (${prefix_info}):"

  # Build the scripts:
  #  export.sql: run on the source database, exports all the tables in a single transaction
  #  import.sql: run on the target database in a single transaction, see import-data-table.sql.tmpl
  #  owner.sql: run on the source database after the import, changes the owner of the imported tables
  echo "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;" > "${work_dir}/export.sql"
  : > "${work_dir}/import.sql"
  : > "${work_dir}/owner.sql"

  while IFS='|' read -r id src_table target_table; do
    data_file="${work_dir}/${id}.copy"

    echo "SELECT '    ' || count(*) || ' rows exported from ${src_schema}.${src_table}' FROM ${src_schema}.${src_table};" >> "${work_dir}/export.sql"
    echo "\\copy ${src_schema}.${src_table} TO '${data_file}'" >> "${work_dir}/export.sql"
    SOURCE_TABLE="${src_schema}.${src_table}" TARGET_SCHEMA=$target_schema TARGET_TABLE=$target_table DATA_FILE=$data_file IMPORT_ID=$id \
      envsubst < import-data-table.sql.tmpl >> "${work_dir}/import.sql"
    echo "ALTER TABLE ${src_schema}.${src_table} OWNER TO ${POSTGRES_USER};" >> "${work_dir}/owner.sql"
  done <<< "$pending_tables"

  echo "COMMIT;" >> "${work_dir}/export.sql"

  # Run the scripts
  run_psql "$src_db" -f "${work_dir}/export.sql" || {
    echo "Error: could not export the data from database ${src_db}" >&2
    exit 1
  }
  run_psql "$target_db" --single-transaction -f "${work_dir}/import.sql" || {
    echo "Error: could not import the data into database ${target_db}, nothing was imported" >&2
    exit 1
  }
  run_psql "$src_db" -f "${work_dir}/owner.sql" || echo "Warning: could not change the owner of the imported tables in database ${src_db}" >&2
done <<< "$pending_sources"

echo "Data import into ${target_db} done:"
log_data_imports
