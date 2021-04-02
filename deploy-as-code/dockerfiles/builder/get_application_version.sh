#!/bin/sh

#!/bin/sh

if [ -z "$1" ]; then
    FOLDER=
else
    FOLDER=$1/
fi

if [ -f "${FOLDER}pom.xml" ]; then
    cat ${FOLDER}pom.xml | oq -i xml -r '.project.version' | cut -d'-' -f1
elif [ -f "${FOLDER}package.json" ]; then
    cat ${FOLDER}package.json | jq -r '.version'
elif [ -f "${FOLDER}VERSION" ]; then
    cat ${FOLDER}VERSION
else
    echo "NA"
fi