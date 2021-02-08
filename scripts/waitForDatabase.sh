#!/bin/bash

set +e

export PGPASSWORD="$POSTGRES_PASSWORD"
for i in {1..30}
   do
      psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB -qt -c "SELECT 0"
      if [ 0 == "$?" ]; then
         echo 'Database ready'
         exit 0
      fi
      echo "Retrying database connection. Attempt $i of 30"
      sleep 1s
   done

exit -1

