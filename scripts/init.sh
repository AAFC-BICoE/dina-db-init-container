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
  ./createDinaDatabase.sh ${curr_db} ${!mu_var} ${!mu_pwd_var} ${!wu_var} ${!wu_pwd_var}
done

