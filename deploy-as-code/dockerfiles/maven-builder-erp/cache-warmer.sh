#!/bin/bash
filename=$1
sed -i "s/TOKEN/$2/g" $filename
while read line; 
do
git clone -b master $line apps
find -name "*pom.xml" -print>files.txt
while read line;
do
echo $line
cp $line .
mvn -B dependency:go-offline
done < files.txt
rm -rf apps
done < $filename