import argparse
import os
import sys
import tempfile
import yaml
import shlex

from jinja2 import Environment, FileSystemLoader
from subprocess import Popen, PIPE

parser = argparse.ArgumentParser()

def find_manifest_path(microservice_name):
    path = os.path.dirname(os.path.abspath(__file__))
    for dir_path, subdirs, files in os.walk(path):
        for f in files:
            if f == "{}.yml".format(microservice_name):
                return "{}/{}".format(dir_path, f)
    raise Exception("Manifest not found")


def parse_args():
    parser.add_argument("-e", "--env", help="environment to apply against")
    parser.add_argument("-m", "--microservice", help="microservice to apply")
    parser.add_argument("-n", "--namespace", help="namespace of microservice")
    parser.add_argument("-i", "--image", help="docker image of microservice")
    parser.add_argument("-dmi", "--db-migration-image", help="docker image of microservice db migration")
    parser.add_argument("-d", "--dry-run", help="Do not apply. Just print all manifests to be applied",
                        action="store_true")

    return parser.parse_args()


def validate_args(args):
    if not (args.env and args.microservice):
        print "env and microservice need to be specfied."
        parser.print_help()
        sys.exit(1)
    if not args.namespace:
        args.namespace = "egov"


def find_config_vars(args):
    dir_path = os.path.dirname(os.path.abspath(__file__))
    env_file_path = "{}/conf/{}.yml".format(dir_path, args.env)
    if not os.path.isfile(env_file_path):
        raise Exception("No config found for env - {}".format(args.env))
    conf = yaml.load(open(env_file_path, "r"))
    if not conf.has_key(args.microservice):
        conf[args.microservice] = {}
    if args.image:
        conf[args.microservice]['image'] = args.image
    if args.db_migration_image:
        conf[args.microservice]['db_migration_image'] = args.db_migration_image
    return conf


def apply_manifest(manifest):
    with tempfile.NamedTemporaryFile() as temp:
        temp.write(manifest)
        temp.flush()
        apply_cmd = "kubectl apply -f {}".format(temp.name)
        out, err = (Popen(shlex.split(apply_cmd),
                          stdout=PIPE).communicate())
        print out
        if err:
            raise Exception("Apply failed\n"
                            "STDOUT:{}\nERROR:{}".
                            format(out, err))


def main():
    args = parse_args()
    validate_args(args)
    manifest_path = find_manifest_path(args.microservice)
    conf = find_config_vars(args)
    env = Environment(loader=FileSystemLoader("/"),
                      trim_blocks=True)

    manifest = env.get_template(manifest_path).render(conf=conf)
    if args.dry_run:
        print manifest
    else:
        apply_manifest(manifest)


if __name__ == "__main__":
    main()
