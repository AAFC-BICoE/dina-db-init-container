# dina-db-init-container
init-container used to manage DINA databases for dev/test env. 

init containers: specialized containers that run before application containers and can contain utilities or setup scripts not present in an app image.

Source: https://docs.okd.io/latest/nodes/containers/nodes-containers-init.html

## Description

This init-container is used to setup DINA databases, in a standard way, on a specific Postgres database server. If a specific database already exist, the int-container will simply skip it. It is possible to create more than one databases for the same module using a prefix.

## Environment Variables

List (space separated) of all DINA databases to create:

`DINA_DB=agent collection`

Variables pattern using the database as suffix: 

```
MIGRATION_USER_dbname
MIGRATION_USER_PW_dbname
WEB_USER_dbname
WEB_USER_PW_dbname
```

A prefix for the database name can also be provided:

```
PREFIX_dbname
```

1 Postgres extension can be added (currently limited to 1):

```
PG_EXTENSION_dbname
```
Note that the extension must be available on the server.

## Example

Build dina-db-init-container container:
`docker build -t aafcbicoe/dina-db-init-container:dev .`

See `docker-compose` file in the `example` folder.


# Version 2
v2 aims at making db-init-container more generic so it can be used to setup databases that are not used by a dina module.

The following environment variables will use the already existing `mydb` to create the provided user (including `GRANT CONNECT`).
```
USE_V2: true
POSTGRES_DB: mydb
POSTGRES_USER: pguser
POSTGRES_PASSWORD: pg1234
POSTGRES_HOST: dina-db

DB_USER: my_user
DB_PASSWORD: secret_password
```

It is also possible to create a new database by additionally setting the variable `DB_NAME`. In that case, 
the user will be granted connect on that database.

# RESTORE_DB
Restore_DB aims at making db-init-container more flexible for deployment in allowing the database to be restore from a pg_dumpall generated backup.
That way it can be used to replicate databases that require issue replication and/or assist in recovery scenarios.

The first two environment variables below are needed for this feature, where a flag is set to enable the feature and the a file path is provided with the mounted
dump file within the container.
```
RESTORE_DB: true
DB_DUMP_FILE_PATH: "/opt/pgrestore/data/sql_dump.sql"

POSTGRES_DB: mydb
POSTGRES_USER: pguser
POSTGRES_PASSWORD: pg1234
POSTGRES_HOST: dina-db

DB_USER: my_user
DB_PASSWORD: secret_password
```
