import json
import os
import sys
import shlex
from subprocess import PIPE, Popen


def get_service_images():
    group = sys.argv[1]
    get_manifests_cmd = "kubectl get deployments --namespace=egov -l " \
                        "'group in ({})' " \
                        "-o json".format(group)
    filter_manifests_cmd = "jq '.items | " \
                           "map({service:.metadata.name, images:[.spec.template.spec.containers[].image]})'"
    get_full_manifests = Popen(shlex.split(get_manifests_cmd), stdout=PIPE)
    get_filtered_manifests = Popen(shlex.split(filter_manifests_cmd),
                                   stdin=get_full_manifests.stdout,
                                   stdout=PIPE)
    manifests, error = get_filtered_manifests.communicate()
    if error:
        raise Exception("Manifests doesn't exist for group {}\nERROR:{}"
                        .format(group, error))
    return manifests


def main():
    service_images = get_service_images()
    service_images_file = "{}/service_images.json".format(os.path.dirname(
        os.path.abspath(__file__)))
    try:
        os.remove(service_images_file)
    except:
        pass
    with open(service_images_file, "w") as f:
        f.write(service_images)


if __name__ == "__main__":
    if not len(sys.argv) == 2:
        print "Error: group not specified"
        print "Usage: python deploy.py <comma separated groups>"
        sys.exit(1)
    main()
