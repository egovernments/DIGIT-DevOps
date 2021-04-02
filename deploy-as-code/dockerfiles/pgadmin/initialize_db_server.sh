#!/bin/sh

# Disable saving of DB passwords
sed -i 's/ALLOW_SAVE_PASSWORD = True/ALLOW_SAVE_PASSWORD = False/g' /pgadmin4/config.py
#Setup DB
python /opt/pgadmin/init.py
