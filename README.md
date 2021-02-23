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
