#! /bin/bash

./waitForDatabase.sh

export PGPASSWORD="$POSTGRES_PASSWORD"
export MIGRATION_USER=migration_user
export WEB_USER=web_user

./createDinaDatabase.sh agent mu_test_pwd wu_test_pwd



