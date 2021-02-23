#! /bin/bash

./waitForDatabase.sh

export PGPASSWORD="$POSTGRES_PASSWORD"
export MIGRATION_USER=migration_user
export WEB_USER=web_user
db_array=($DINA_DB)
for curr_db in ${db_array[@]}; do
  echo "DINA database : ${curr_db}"
  mu_var=MIGRATION_USER_${curr_db}
  mu_pwd_var=MIGRATION_USER_PW_${curr_db}
  wu_var=WEB_USER_${curr_db}
  wu_pwd_var=WEB_USER_PW_${curr_db}
  db_schema_name=${curr_db}

  db_prefix_var=PREFIX_${curr_db}
  db_prefix=${!db_prefix_var}

  if [ -n "$db_prefix" ]; then
    echo "Database prefix provided : ${db_prefix}"
    curr_db=${db_prefix}_${curr_db}
  fi

  ./createDinaDatabase.sh ${curr_db} ${db_schema_name} ${!mu_var} ${!mu_pwd_var} ${!wu_var} ${!wu_pwd_var}

  pg_ext_var=PG_EXTENSION_${curr_db}
  pg_ext=${!pg_ext_var}
  if [ -n "$pg_ext" ]; then
    echo "Postgres Extension : ${pg_ext}"
    ./createPostgreExtension.sh ${pg_ext} ${curr_db} ${db_schema_name}
  fi

done

