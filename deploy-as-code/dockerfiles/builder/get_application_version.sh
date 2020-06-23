#!/bin/sh

if [ -f "$1pom.xml" ]; then
    cat pom.xml | oq -i xml -r '.project.version' | cut -d'-' -f1
elif [ -f "$1package.json" ]; then
    cat package.json | jq -r '.version'
else
    echo "NA"
fi