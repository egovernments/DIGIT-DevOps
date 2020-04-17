import json
import os
import shlex
import sys
from subprocess import Popen, PIPE


def deploy():
    env = sys.argv[1]
    service_images_file = "{}/service_images.json".format(
        os.path.dirname(os.path.abspath(__file__)))
    with open(service_images_file) as service_images_json:
        service_images = json.load(service_images_json)

    apply_script_file = "{}/apply.py".format(
        os.path.dirname(os.path.abspath(__file__)))
    for service_image in service_images:
        service = service_image['service']
        images = ",".join(service_image['images'])
        if len(service_image['images'][0].split(":")) > 1:
            service_image_name, tag = service_image['images'][0].split(":")
        else:
            service_image_name = service_image['images'][0].split(":")
            tag = "latest"
        db_migration_image = "{}-db:{}".format(service_image_name, tag)
        deployment_cmd = "python {} -e {} -m {} -i {} -dmi {} -conf -secret".format(
            apply_script_file, env, service, images, db_migration_image)
        out, err = (Popen(shlex.split(deployment_cmd), stdout=PIPE).communicate())
        if err:
            raise Exception("Deployment failed\n"
                            "STDOUT:{}\nERROR:{}".
                            format(out, err))
        print out


if __name__ == "__main__":
    if not len(sys.argv) == 2:
        print "Error: env not specified"
        print "Usage: python deploy.py <env>"
        sys.exit(1)
    deploy()
