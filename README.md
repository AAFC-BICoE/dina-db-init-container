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

# Postgres Database Server

Information about the Postgres Database Server and the default database.
This section is mandatory for all operations.

```
POSTGRES_DB: mydb
POSTGRES_USER: pguser
POSTGRES_PASSWORD: pg1234
POSTGRES_HOST: dina-db
```

# Non-DINA database
`db-init-container` can be used to setup databases that are not used by a dina module (e.g. Keycloak database).

The following environment variables will use the already existing `mydb` to create the provided user (including `GRANT CONNECT`).
```
DB_USER: my_user
DB_PASSWORD: secret_password
```

It is also possible to create a new database by additionally setting the variable `DB_NAME`. In that case, 
the user will be granted connect on that database.

# RESTORE_DB
Allows to restore the database from a pg_dumpall generated backup.
That way it can be used to replicate databases that require issue replication and/or assist in recovery scenarios.

The mounted SQL dump file must be encoded in base64. The file can be converted using:

```
base64 sql_dump.sql > sql_dump.sql.b64
```

The first two environment variables below are needed for this feature, where a flag is set to enable the feature and the a file path is provided with the mounted dump file within the container.

```
RESTORE_DB: true
DB_DUMP_FILE_PATH: "/opt/pgrestore/data/sql_dump.sql.b64"
```

Note: the backup file from pg_dumpall will include all the users and credentials from the previous installation. If credentials are unknown,
the `db-init-container` can reset them, so they are synchronized with the new deployment environment variables.

# RESET_USERS

Reset user's credentials with the ones in the environment variables.

For DINA module, the following would reset the credentials for the collection module:
```
RESET_USERS: true
DINA_DB: collection
MIGRATION_USER_collection: mu_coll
MIGRATION_USER_PW_collection: new_mu_password
WEB_USER_collection: wu_coll
WEB_USER_PW_collection: new_wu_password
```
