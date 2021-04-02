#!/bin/sh

git log --oneline -- $1| awk 'NR==1{print $1}'