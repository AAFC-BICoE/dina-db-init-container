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

if [ "$(run_psql "$target_db" -c "SELECT to_regclass('${data_import_table}') IS NOT NULL")" != "t" ]; then
  exit 0
fi

work_dir=$(mktemp -d) || exit 1
trap 'rm -rf "$work_dir"' EXIT

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
  echo "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;" > "${work_dir}/export.sql"
  : > "${work_dir}/import.sql"
  : > "${work_dir}/owner.sql"

  while IFS='|' read -r id src_table target_table; do
    echo "  ${src_schema}.${src_table} -> ${target_schema}.${target_table}"
    echo "\\copy ${src_schema}.${src_table} TO '${work_dir}/${id}.copy'" >> "${work_dir}/export.sql"
    echo "\\copy ${target_schema}.${target_table} FROM '${work_dir}/${id}.copy'" >> "${work_dir}/import.sql"
    # move the sequences of the target table columns (serial/identity) after the imported values
    echo "SELECT format('SELECT setval(%L, max(%I)) FROM %s', pg_get_serial_sequence(attrelid::regclass::text, attname), attname, attrelid::regclass) FROM pg_attribute WHERE attrelid = '${target_schema}.${target_table}'::regclass AND attnum > 0 AND NOT attisdropped AND pg_get_serial_sequence(attrelid::regclass::text, attname) IS NOT NULL \\gexec" >> "${work_dir}/import.sql"
    echo "UPDATE ${data_import_table} SET status = 'IMPORTED', processed_on = now() WHERE id = ${id};" >> "${work_dir}/import.sql"
    echo "ALTER TABLE ${src_schema}.${src_table} OWNER TO ${POSTGRES_USER};" >> "${work_dir}/owner.sql"
  done < <(run_psql "$target_db" -c "SELECT id, source_table, target_table FROM ${data_import_table} WHERE ${pending} ORDER BY id")

  echo "COMMIT;" >> "${work_dir}/export.sql"

  run_psql "$src_db" -f "${work_dir}/export.sql" > /dev/null || exit 1
  run_psql "$target_db" --single-transaction -f "${work_dir}/import.sql" > /dev/null || exit 1
  run_psql "$src_db" -f "${work_dir}/owner.sql" > /dev/null
done < <(run_psql "$target_db" -F ' ' -c "SELECT DISTINCT source_database, source_schema FROM ${data_import_table} WHERE status IS NULL")
