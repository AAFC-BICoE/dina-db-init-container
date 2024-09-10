#! /bin/bash

./waitForDatabase.sh

export PGPASSWORD="$POSTGRES_PASSWORD"
export MIGRATION_USER=migration_user
export WEB_USER=web_user

if [ -n "$USE_V2" ]; then
  echo "Using script v2"

  if [ -n "$DB_NAME" ]; then
    ./createDatabase.sh "${DB_NAME}"
    ./createUser.sh "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}"
  else
     echo "Using existing database $POSTGRES_DB"
    ./createUser.sh "${POSTGRES_DB}" "${DB_USER}" "${DB_PASSWORD}"
  fi
elif [ -n "$PG_RESTORE" ]; then
  if [ -n "$PG_DUMP_PATH" ]; then
    # Check if the dump file is non-null
    if [ ! -s "$PG_DUMP_PATH" ]; then
      echo "The dump file is null or does not exist. Skipping restore..."
    else
      ./createDatabase.sh "${POSTGRES_DB}"
      ./restoreDatabase.sh "${PG_DUMP_PATH}"
    fi
  else
    echo "PG_DUMP_PATH is not set. Skipping restore..."
  fi
else
  db_array=($DINA_DB)
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

    ./createDinaDatabase.sh ${curr_db} ${db_schema_name} ${!mu_var} ${!mu_pwd_var} ${!wu_var} ${!wu_pwd_var}

    if [ -n "$pg_ext" ]; then
      echo "Postgres Extension : ${pg_ext}"
      ./createPostgreExtension.sh ${pg_ext} ${curr_db} ${db_schema_name}
    fi
  done
fi
