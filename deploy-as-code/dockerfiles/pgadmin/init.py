from pgAdmin4 import app
import os
import simplejson as json
import re

from flask import current_app
from flask_security.utils import encrypt_password

import config

from pgadmin.model import db, Role, User, UserPreference, Server, \
    ServerGroup, Process, Setting
import builtins
builtins.SERVER_MODE = True


def load_envs():
    if not (os.environ['SERVER_NAME'] and os.environ['SERVER_HOST'] and os.environ['SERVER_PORT']
            and os.environ['MAINTENANCE_DB_NAME'] and os.environ['DB_ADMIN_USERNAME'] and os.environ['DB_READ_USERNAME']
            and os.environ['PGADMIN_READ_EMAIL'] and os.environ['PGADMIN_READ_PASSWORD']):
        quit()
    else:
        dict = {
            "serverName": os.environ['SERVER_NAME'],
            "serverHost": os.environ['SERVER_HOST'],
            "serverPort": os.environ['SERVER_PORT'],
            "serverMaintenanceDb": os.environ['MAINTENANCE_DB_NAME'],
            "adminDBUsername": os.environ['DB_ADMIN_USERNAME'],
            "readDBUsername": os.environ['DB_READ_USERNAME'],
            "pgAdminReadEmail": os.environ['PGADMIN_READ_EMAIL'],
            "pgAdminReadPassword": os.environ['PGADMIN_READ_PASSWORD'],
        }

        return dict


def insert_user(envs, encryptedPwd):
    db.engine.execute(
        """ INSERT INTO "user" VALUES(2, '%s', '%s', 1, NULL) """ % (envs["pgAdminReadEmail"], encryptedPwd))

    db.engine.execute("""
INSERT INTO "roles_users"
VALUES(2, 2);
    """)


def insert_servers(envs):
    db.engine.execute(""" DELETE FROM "servergroup" """)

    db.engine.execute("""
    INSERT INTO "servergroup"
    VALUES(1, 1, '%s')
    """ % (envs["serverName"]))

    db.engine.execute("""
    INSERT INTO "servergroup"
    VALUES(2, 2, '%s')
    """ % (envs["serverName"] + "_READ"))

    db.engine.execute(
        """ INSERT INTO server (id, user_id, servergroup_id, name, host, port, maintenance_db, username, password, ssl_mode, service) VALUES (1, 1, 1, '%s', '%s', '%s', '%s', '%s', null, 'prefer', null) """ % (envs["serverName"], envs["serverHost"], envs["serverPort"], envs["serverMaintenanceDb"], envs["adminDBUsername"]))

    db.engine.execute(
        """ INSERT INTO server (id, user_id, servergroup_id, name, host, port, maintenance_db, username, password, ssl_mode, service) VALUES (2, 2, 2, '%s', '%s', '%s', '%s', '%s', null, 'prefer', null) """ % (envs["serverName"], envs["serverHost"], envs["serverPort"], envs["serverMaintenanceDb"], envs["readDBUsername"]))


if __name__ == '__main__':

    envs = load_envs()

    with app.app_context():
        encryptedPwd = encrypt_password(envs["pgAdminReadPassword"])

        insert_user(envs, encryptedPwd)

        insert_servers(envs)
