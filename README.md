# dina-db-init-container
init-container used to manage DINA databases for dev/test env. 

init containers: specialized containers that run before application containers and can contain utilities or setup scripts not present in an app image.

Source: https://docs.okd.io/latest/nodes/containers/nodes-containers-init.html

## Environment Variables

List (space separated) of all DINA databases to create:

`DINA_DB=agent collection`

User variable pattern using the database as suffix: 

```
MIGRATION_USER_dbname
MIGRATION_USER_PW_dbname
WEB_USER_dbname
WEB_USER_PW_dbname
```

## Example

Build dina-db-init-container container:
`docker build -t aafcbicoe/dina-db-init-container:dev .`

See `docker-compose` file in the `example` folder.
