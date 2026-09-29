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
#
# arguments: (1) target database name, (2) target schema name

set -o pipefail

export PGPASSWORD="$POSTGRES_PASSWORD"

target_db=$1
target_schema=$2
data_import_table="${target_schema}.dina_data_import"

run_psql() {
  local db=$1
  shift
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -v ON_ERROR_STOP=1 -qtA "$db" "$@"
}

# Nothing to import if the module didn't create the dina_data_import table
if [ "$(run_psql "$target_db" -c "SELECT to_regclass('${data_import_table}') IS NOT NULL")" != "t" ]; then
  exit 0
fi

work_dir=$(mktemp -d) || exit 1
trap 'rm -rf "$work_dir"' EXIT

# For each source database with pending tables
while read -r src_base_db src_schema; do
  prefix_var="PREFIX_${src_base_db}"
  src_db=${src_base_db}
  [ -n "${!prefix_var}" ] && src_db=${!prefix_var}_${src_base_db}
  pending="source_database = '${src_base_db}' AND source_schema = '${src_schema}' AND status IS NULL"

  if [ "$(run_psql "$POSTGRES_DB" -c "SELECT 1 FROM pg_database WHERE datname = '${src_db}'")" != "1" ]; then
    echo "Source database ${src_db} does not exist, marking as SOURCE_NOT_FOUND"
    run_psql "$target_db" -c "UPDATE ${data_import_table} SET status = 'SOURCE_NOT_FOUND', processed_on = now() WHERE ${pending}" || exit 1
    continue
  fi

  echo "Importing data from database ${src_db} into database ${target_db}"

  # Build the scripts:
  #  export.sql: run on the source database, exports all the tables in a single transaction
  #  import.sql: run on the target database in a single transaction, see import-data-table.sql.tmpl
  #  owner.sql: run on the source database after the import, changes the owner of the imported tables
  echo "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;" > "${work_dir}/export.sql"
  : > "${work_dir}/import.sql"
  : > "${work_dir}/owner.sql"

  while IFS='|' read -r id src_table target_table; do
    echo "  ${src_schema}.${src_table} -> ${target_schema}.${target_table}"
    data_file="${work_dir}/${id}.copy"

    echo "\\copy ${src_schema}.${src_table} TO '${data_file}'" >> "${work_dir}/export.sql"
    SOURCE_TABLE="${src_schema}.${src_table}" TARGET_SCHEMA=$target_schema TARGET_TABLE=$target_table DATA_FILE=$data_file IMPORT_ID=$id \
      envsubst < import-data-table.sql.tmpl >> "${work_dir}/import.sql"
    echo "ALTER TABLE ${src_schema}.${src_table} OWNER TO ${POSTGRES_USER};" >> "${work_dir}/owner.sql"
  done < <(run_psql "$target_db" -c "SELECT id, source_table, target_table FROM ${data_import_table} WHERE ${pending} ORDER BY id")

  echo "COMMIT;" >> "${work_dir}/export.sql"

  # Run the scripts
  run_psql "$src_db" -f "${work_dir}/export.sql" > /dev/null || exit 1
  run_psql "$target_db" --single-transaction -f "${work_dir}/import.sql" > /dev/null || exit 1
  run_psql "$src_db" -f "${work_dir}/owner.sql" > /dev/null
done < <(run_psql "$target_db" -F ' ' -c "SELECT DISTINCT source_database, source_schema FROM ${data_import_table} WHERE status IS NULL")
