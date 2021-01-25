#! /bin/sh

export WEB_USER=web_user
export MIGRATION_USER=migration

DINA_DB=agent envsubst < db-init.sql.tmpl
DINA_DB=agent SCHEMA=agent MIGRATION_USER_PW=123 WEB_USER_PW=123 envsubst < init-dina-module-db.sql.tmpl

