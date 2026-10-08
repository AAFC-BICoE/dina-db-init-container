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

A prefix for the database name can also be provided, the database is then named `<prefix>_<dbname>` (the schema keeps the name without prefix):

```
PREFIX_dbname

PREFIX_collection: v0    # database v0_collection, schema collection
```

Multiple Postgres extensions can be added, seperate multiple extention declarations with a space:

```
PG_EXTENSION_dbname: MyExtention1 MyOtherExtention
```
Note that the extension must be available on the server.

## Data import

Data from other DINA database(s) can be imported (copied) into the tables of a DINA database. There is no environment variable, the
import is requested by the module itself (e.g. with Liquibase) by creating the target tables and the following table in its schema:

```sql
CREATE TABLE dina_data_import (
  id SERIAL PRIMARY KEY,
  source_database varchar(100) NOT NULL, -- name without prefix, e.g. loan_transaction (not v0_loan_transaction)
  source_schema varchar(100) NOT NULL,
  source_table varchar(100) NOT NULL,
  target_table varchar(100) NOT NULL,    -- in the same schema as dina_data_import
  status varchar(50),                    -- null means pending
  processed_on timestamptz
);
```

For each source database with pending rows:
 - If the source database doesn't exist, the rows are marked as `SOURCE_NOT_FOUND` (e.g. a new installation without the source module).
 - The source tables are read in a single transaction. The target tables must be empty and have the same structure (columns and order) as the source tables.
 - The target tables are loaded and the rows marked as `IMPORTED` in a single transaction, in the order of the `dina_data_import` ids. Foreign keys are checked, so parent tables must be declared before their children.
 - Data is copied as is, including ids, so the relationships are kept. The sequences of the target columns (`SERIAL`/identity) are moved after the imported values. Other sequences (not owned by a column) are not modified.
 - The imported source tables become owned by `POSTGRES_USER` to identify them as imported. The source database is not modified otherwise.

Since the init-container runs before the module, the tables created by the module (e.g. Liquibase) are only found on the next run.

### Prefixes

The import runs in the init-db of the **target** database, so the prefix of the **source** database must be known there:
`PREFIX_<source_database>` is read from the environment of that init-db (`source_database` itself never contains the prefix).

The source and target databases must both have a prefix or both have none. If only one of them has a prefix, the import is
refused: the init-db fails with an error and the rows stay pending, so the import is done once the configuration is fixed.

When all the databases are created by the same init-db (e.g. docker-compose), all the `PREFIX_*` variables are usually already there.
When each module has its own init-db (e.g. an init container per deployment in Kubernetes/OKD), the init-db of the target module
also needs the prefix of the source database. For example, for collection importing from loan_transaction:

```yaml
- name: DINA_DB
  value: collection
- name: PREFIX_collection
  value: v0                  # database v0_collection
- name: PREFIX_loan_transaction
  value: v0                  # required to import from v0_loan_transaction
```

### Logs

Each run logs the rows of `dina_data_import`, the source database used and the number of rows exported and imported:

```
Data import into v0_collection:
  #1 loan_transaction.transaction -> collection.transaction: pending
  Importing from database v0_loan_transaction (PREFIX_loan_transaction=v0):
    39 rows exported from loan_transaction.transaction
    39 rows imported into collection.transaction
Data import into v0_collection done:
  #1 loan_transaction.transaction -> collection.transaction: IMPORTED on 2026-10-05 18:07:29 UTC
```

### Running an import again

Do not edit `source_database`, `source_schema` or the table names by hand, they must match exactly (no extra spaces).
To run an import again (e.g. after a `SOURCE_NOT_FOUND` caused by a missing prefix), make sure the target tables are empty,
set the row back to pending and restart the init-db:

```sql
UPDATE collection.dina_data_import SET status = NULL, processed_on = NULL WHERE id = 1;
```

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
