#!/bin/bash

# Imports (copies) data from other DINA database(s) into the tables of a DINA database.
#
# What to import is declared by the module itself (e.g. with Liquibase) in the table <schema>.dina_data_import
# of the target database. Each pending row (status is null) declares a source table to copy into a target table
# (created by the module, so it already has the right ownership):
#   source_database, source_schema, source_table, target_table, status, processed_on
#
# For each source database:
#  - if the source database doesn't exist, pending rows are marked as SOURCE_NOT_FOUND
#  - source tables are read in a single (repeatable read) transaction, only columns also present in the target table are copied
#  - target tables are loaded and the rows marked as IMPORTED in a single transaction
#  - imported source tables become owned by $POSTGRES_USER to identify them as imported
#
# arguments: (1) target database name, (2) target schema name

set -o pipefail

export PGPASSWORD="$POSTGRES_PASSWORD"

target_db=$1
target_schema=$2

if [ -z "$target_db" ] || [ -z "$target_schema" ]; then
  echo "Error: importDinaData.sh requires target database and target schema" >&2
  exit 1
fi

run_psql() {
  local db=$1
  shift
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -v ON_ERROR_STOP=1 -qtA "$db" "$@"
}

import_table="${target_schema}.dina_data_import"

import_table_exists=$(run_psql "$target_db" -c "SELECT to_regclass('${import_table}') IS NOT NULL") || exit 1
if [ "$import_table_exists" != "t" ]; then
  exit 0
fi

sources=$(run_psql "$target_db" -c "SELECT DISTINCT source_database || ' ' || source_schema FROM ${import_table} WHERE status IS NULL") || exit 1
if [ -z "$sources" ]; then
  echo "No pending data import for database ${target_db}"
  exit 0
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/import_data_XXXXXX") || exit 1
trap 'rm -rf "$work_dir"' EXIT

while read -r src_base_db src_schema; do
  src_prefix_var="PREFIX_${src_base_db}"
  src_db=${src_base_db}
  if [ -n "${!src_prefix_var}" ]; then
    src_db=${!src_prefix_var}_${src_base_db}
  fi
  pending_condition="source_database = '${src_base_db}' AND source_schema = '${src_schema}' AND status IS NULL"

  echo "Import data from database ${src_db} (schema ${src_schema}) into database ${target_db}"

  src_db_exists=$(run_psql "$POSTGRES_DB" -c "SELECT 1 FROM pg_database WHERE datname = '${src_db}'") || exit 1
  if [ "$src_db_exists" != "1" ]; then
    echo "Source database ${src_db} does not exist. Marking as SOURCE_NOT_FOUND"
    run_psql "$target_db" -c "UPDATE ${import_table} SET status = 'SOURCE_NOT_FOUND', processed_on = current_timestamp WHERE ${pending_condition}" || exit 1
    continue
  fi

  export_file="${work_dir}/export_${src_db}.sql"
  import_file="${work_dir}/import_${src_db}.sql"
  echo "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;" > "$export_file"
  : > "$import_file"
  imported_ids=()
  imported_source_tables=()

  while IFS='|' read -r id src_table target_table; do
    src_columns=$(run_psql "$src_db" -c "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = '${src_schema}' AND table_name = '${src_table}'") || exit 1
    if [ -z "$src_columns" ]; then
      echo "Source table ${src_schema}.${src_table} does not exist. Marking as SOURCE_NOT_FOUND"
      echo "UPDATE ${import_table} SET status = 'SOURCE_NOT_FOUND', processed_on = current_timestamp WHERE id = ${id};" >> "$import_file"
      continue
    fi

    # columns present in both tables, in the order of the target table
    columns=$(run_psql "$target_db" -c "SELECT string_agg(quote_ident(column_name), ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = '${target_schema}' AND table_name = '${target_table}' AND column_name = ANY(string_to_array('${src_columns}', ','))") || exit 1
    if [ -z "$columns" ]; then
      echo "Error: target table ${target_schema}.${target_table} does not exist or has no column in common with ${src_schema}.${src_table}" >&2
      exit 1
    fi

    echo "  ${src_schema}.${src_table} -> ${target_schema}.${target_table} (${columns})"
    data_file="${work_dir}/${src_db}_${id}.copy"
    echo "\\copy (SELECT ${columns} FROM \"${src_schema}\".\"${src_table}\") TO '${data_file}'" >> "$export_file"
    echo "\\copy \"${target_schema}\".\"${target_table}\" (${columns}) FROM '${data_file}'" >> "$import_file"
    imported_ids+=("$id")
    imported_source_tables+=("\"${src_schema}\".\"${src_table}\"")
  done < <(run_psql "$target_db" -c "SELECT id, source_table, target_table FROM ${import_table} WHERE ${pending_condition} ORDER BY id")

  echo "COMMIT;" >> "$export_file"
  if [ ${#imported_ids[@]} -gt 0 ]; then
    ids_csv=$(IFS=','; echo "${imported_ids[*]}")
    echo "UPDATE ${import_table} SET status = 'IMPORTED', processed_on = current_timestamp WHERE id IN (${ids_csv});" >> "$import_file"
  fi

  run_psql "$src_db" -f "$export_file" > /dev/null || {
    echo "Error: Failed to export data from database ${src_db}" >&2
    exit 1
  }

  run_psql "$target_db" --single-transaction -f "$import_file" > /dev/null || {
    echo "Error: Failed to import data from database ${src_db} into database ${target_db}" >&2
    exit 1
  }

  # Identify the source tables as imported
  for src_table in "${imported_source_tables[@]}"; do
    run_psql "$src_db" -c "ALTER TABLE ${src_table} OWNER TO \"${POSTGRES_USER}\"" > /dev/null || \
      echo "Warning: Failed to change the owner of ${src_table} in database ${src_db}" >&2
  done

  echo "Data imported from database ${src_db} into database ${target_db}"
done <<< "$sources"
