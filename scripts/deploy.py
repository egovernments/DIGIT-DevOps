import argparse
import os
import re
import shlex
import sys
import tempfile
from subprocess import Popen, PIPE
from threading import Timer

from render import render_manifest

IGNORE_PATTERNS = r'\.DS_Store'
parser = argparse.ArgumentParser()


def get_all_manifests():
    path = "{}/../cluster/app".format(os.path.dirname(os.path.abspath(__file__)))
    for dir_path, subdirs, files in os.walk(path):
        for f in files:
            if re.match(IGNORE_PATTERNS, f):
                continue
            yield f, dir_path


def find_manifest_path(microservice_name):
    for f, dir_path in get_all_manifests():
        if f == "{}.yml".format(microservice_name):
            return "{}/{}".format(dir_path, f)
    raise Exception("Manifest not found")


def parse_args():
    parser.add_argument("-e", "--env", help="environment to apply against")
    parser.add_argument("-n", "--namespace", help="namespace of microservice")
    parser.add_argument("-m", "--microservice", help="microservice to apply")
    parser.add_argument("-i", "--images", help="comma separated list of docker images for microservice")
    parser.add_argument("-dmi", "--db-migration-image", help="docker image of microservice db migration")
    parser.add_argument("-endmi", "--env-specific-db-migration-image",
                        help="docker image of additional microservice db migration for hybrid environments")
    parser.add_argument("-d", "--dry-run", help="Do not apply. Just print all manifests to be applied",
                        action="store_true")
    parser.add_argument("-conf", "--with_configmap", help="Attach configMaps to manifest",
                        action="store_true")
    parser.add_argument("-secret", "--with_secrets", help="Attach secrests to manifest",
                        action="store_true")
    parser.add_argument("-vol", "--with_volumes", help="Attach volumes to manifest",
                        action="store_true")

    return parser.parse_args()


def validate_args(args):
    if not args.env:
        print "env and microservice need to be specfied."
        parser.print_help()
        sys.exit(1)
    if not (args.microservice):
        print "Either a microservice name or 'all' has to be specified to apply manifests for"
        parser.print_help()
        sys.exit(1)
    if not args.namespace:
        args.namespace = "egov"


def apply_manifest(manifest):
    with tempfile.NamedTemporaryFile() as temp:
        temp.write(manifest)
        temp.flush()
        apply_cmd = "kubectl apply -f {}".format(temp.name)
        proc = Popen(shlex.split(apply_cmd), stdout=PIPE)
        out, err = proc.communicate()
        print out
        if not proc.returncode == 0:
            raise Exception("Apply failed\n"
                            "STDOUT:{}\nERROR:{}".
                            format(out, err))


def wait_for_deployment_to_finish(service, namespace):
    deployment_status_cmd = "kubectl rollout status deployment/{} --namespace={}".format(service, namespace)
    proc = Popen(shlex.split(deployment_status_cmd), stdout=PIPE)
    kill_proc = lambda p: p.kill()
    timeout_sec = 300
    timer = Timer(timeout_sec, kill_proc, [proc])
    try:
        timer.start()
        out, err = proc.communicate()
        print out
        if not proc.returncode == 0:
            raise Exception("Error while checking deployment status for service: {}\n{}".format(service, err))
    finally:
        timer.cancel()


def main():
    args = parse_args()
    validate_args(args)
    applicable_manifests = []
    cwd = os.path.dirname(os.path.abspath(__file__))

    applicable_manifests.append(render_manifest(args, manifest_path="{}/../cluster/namespaces.yml".format(cwd)))

    if args.with_configmap:
        applicable_manifests.append(
            render_manifest(args, manifest_path="{}/../cluster/configMaps.yml".format(cwd)))
    if args.with_secrets:
        applicable_manifests.append(
            render_manifest(args, manifest_path="{}/../cluster/secrets.yml".format(cwd)))
    if args.with_volumes:
        applicable_manifests.append(render_manifest(args, manifest_path="{}/../cluster/volumes.yml".format(cwd)))

    applicable_manifests.append(
        render_manifest(args, manifest_path=find_manifest_path(args.microservice)))

    final_manifest = "\n---\n".join(applicable_manifests)

    if args.dry_run:
        print final_manifest
    else:
        apply_manifest(final_manifest)
        wait_for_deployment_to_finish(args.microservice, args.namespace)


if __name__ == "__main__":
    main()
