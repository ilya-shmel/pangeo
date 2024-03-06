#!/bin/bash

SCRIPT_CONTENT=()
SCRIPT_FILE="/opt/pangeoradar/support_tools/opensearch/migration.sh"

## Convert the migration script into an array
readarray -t $SCRIPT_CONTENT < $SCRIPT_FILE    

for $LINE in ${SCRIPT_CONTENT[@]}
do
    echo $LINE
done