#! /bin/bash

# Creates database and users for DINA module
handleDinaModuleDatabase() {
  db_array=("$DINA_DB")
  for curr_db in ${db_array[@]}; do
    echo "DINA database : ${curr_db}"
    mu_var=MIGRATION_USER_${curr_db}
    mu_pwd_var=MIGRATION_USER_PW_${curr_db}
    wu_var=WEB_USER_${curr_db}
    wu_pwd_var=WEB_USER_PW_${curr_db}
    db_schema_name=${curr_db}
    pg_ext_var=PG_EXTENSION_${curr_db}
    pg_ext=${!pg_ext_var}

    db_prefix_var=PREFIX_${curr_db}
    db_prefix=${!db_prefix_var}

    if [ -n "$db_prefix" ]; then
      echo "Database prefix provided : ${db_prefix}"
      curr_db=${db_prefix}_${curr_db}
    fi

    ./createDinaDatabase.sh "${curr_db}" "${db_schema_name}" "${!mu_var}" "${!mu_pwd_var}" "${!wu_var}" "${!wu_pwd_var}"

    if [ -n "$pg_ext" ]; then
      echo "Postgres Extension : ${pg_ext}"
      ./createPostgreExtension.sh "${pg_ext}" "${curr_db}" "${db_schema_name}"
    fi
  done
}

# Creates user and an empty database (if required) for something that is not a DINA module (e.g. Keycloak)
handleGenericDatabase() {
  if [ -n "$DB_NAME" ]; then
    echo "Creating (non-DINA) database $DB_NAME"
    ./createDatabase.sh "${DB_NAME}"
    ./createUser.sh "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}"
  else
     echo "Using existing database $POSTGRES_DB"
    ./createUser.sh "${POSTGRES_DB}" "${DB_USER}" "${DB_PASSWORD}"
  fi
}

# Restore the database from a file represented by the variable $DB_DUMP_FILE_PATH
restoreDatabase() {
  if [ -n "$DB_DUMP_FILE_PATH" ]; then
    # Check if the dump file is non-null
    if [ ! -s "$DB_DUMP_FILE_PATH" ]; then
      echo "The dump file is null or does not exist. Skipping restore..."
    else
      ./restoreDatabase.sh "${DB_DUMP_FILE_PATH}"
    fi
  else
    echo "DB_DUMP_FILE_PATH is not set. Skipping restore..."
  fi
}

# Reset credentials to a new values for DINA users
# DINA user means users of a database that are defined as WebUser(wu) and MigrationUser(mu)
resetDinaUser() {
  db_array=("$DINA_DB")
  for curr_db in ${db_array[@]}; do
    mu_var=MIGRATION_USER_${curr_db}
    mu_pwd_var=MIGRATION_USER_PW_${curr_db}
    wu_var=WEB_USER_${curr_db}
    wu_pwd_var=WEB_USER_PW_${curr_db}
    ./resetUser.sh "${!wu_var}" "${!wu_pwd_var}"
    ./resetUser.sh "${!mu_var}" "${!mu_pwd_var}"
  done
}

resetGenericDatabaseUser() {
  ./resetUser.sh "${DB_USER}" "${DB_PASSWORD}"
}

./waitForDatabase.sh

export PGPASSWORD="$POSTGRES_PASSWORD"
export MIGRATION_USER=migration_user
export WEB_USER=web_user

# Are we restoring a database from a file ?
if [ "${RESTORE_DB,,}" = "true" ]; then
  restoreDatabase
fi

# Check if we are dealing with DINA module database(s)
if [ -n "$DB_NAME" ]; then
  handleDinaModuleDatabase
  # if we need to reset users
  if [ "${RESET_USERS,,}" = "true" ]; then
    resetDinaUser
  fi
# Check if we are dealing with a non-DINA database
elif [ -n "$DB_USER" ]; then
  handleGenericDatabase
  # if we need to reset users
  if [ "${RESET_USERS,,}" = "true" ]; then
    resetGenericDatabaseUser
  fi
fi
