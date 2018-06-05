import argparse
import sys, os
import git
from pathlib import Path
import re
from jinja2 import Environment, FileSystemLoader
import fileinput
import shutil

local_repo='/Users/Senthil/eGov/source/egov-services/'
infraops_repo='/Users/Senthil/eGov/source/eGov-infraOps'

IGNORE_PATTERNS = r'\.DS_Store'
parser = argparse.ArgumentParser()

def parse_args():
    parser.add_argument("-p", "--project", help="Project name")
    parser.add_argument("-s", "--service", help="Service name")
    parser.add_argument("-gw", "--gateway", help="with gateway")
    parser.add_argument("-web", "--web", help="web project")
    return parser.parse_args()

def update_local_repo(git_dir):
    g = git.cmd.Git(git_dir)
    g.pull()

def validate_app_properties(args):
    project_dir = Path("{}/{}",local_repo,args.project)
    if not project_dir.is_dir():
        print 'ERROR: Project directory for ' + args.project + ' doest not exist.'
        sys.exit(0)
    app_properties_file = Path("{}/{}/src/main/resources/application.properties".format(project_dir,args.service))
    project_dir = Path("{}/{}",local_repo,args.project)
    if not app_properties_file.is_file():
        print 'ERROR: Could not find application properties. Please check  ' + str(app_properties_file)
        sys.exit(0)
    else:
        return str(app_properties_file)

def nonblank_lines(f):
    for l in f:
        line = l.rstrip()
        if line:
            if not line.startswith("#"):
                yield line

def process_key(key):
    key = key.upper()
    key = key.replace(".", "_")
    key = key.replace("-", "_")
    return key

def process_property(line):
    result = re.findall("(.*)=(.*)",line)
    for key, value in result:
        key = process_key(key)
    return key, value

def map_project_name(project):
    return {
        'asset': 'asset',
        'billingservices': 'billingservices',
        'collections': 'collections',
        'core': 'core',
        'demand': 'demand',
        'financials': 'financials',
        'gateway': 'gateway',
        'hr': 'hr',
        'hybrid-data-sync': 'hybrid-data-sync',
        'lams': 'lams',
        'pgr': 'pgr',
        'propertytax': 'property',
        'tradelicense': 'tradelicense',
        'user': 'user',
        'wcms': 'wcms',
        'web': 'web',
        'reportinfra': 'reportinfra',
        'citizen': 'citizen',
        'swm': 'swm',
        'lcms': 'lcms',
        'works': 'works',
	'rainmaker': 'rainmaker'
    }.get(project, None)

def check_for_known_keys(key):
    return {
        'SPRING_DATASOURCE_URL': "valueFrom:\n            configMapKeyRef:\n              name: egov-config\n              key: db-url",
        'SPRING_DATASOURCE_USERNAME': "valueFrom:\n            secretKeyRef:\n              name: db\n              key: username",
        'SPRING_DATASOURCE_PASSWORD': "valueFrom:\n            secretKeyRef:\n              name: db\n              key: password",
        'SPRING_DATASOURCE_TOMCAT_INITIAL_SIZE': "valueFrom:\n          configMapKeyRef:\n              name: egov-config\n              key: spring-datasource-tomcat-initialSize",
        'SPRING_DATASOURCE_DRIVER_CLASS_NAME': 1,
        'KAFKA_CONFIG_BOOTSTRAP_SERVER_CONFIG': 1,
        'SPRING_KAFKA_BOOTSTRAP_SERVERS': 1,
        'JAVA_OPTS': 1,
        'SPRING_DATASOURCE_TOMCAT_INITIAL_SIZE': 1,
        'APP_TIMEZONE': 1,
        'SERVER_PORT': 1,

    }.get(key, None)

def append_known_keys(environment_variables,service):

    environment_variables += "\n        - name: SPRING_KAFKA_BOOTSTRAP_SERVERS\n          valueFrom:\n            configMapKeyRef:\n              name: egov-config\n              key: kafka-brokers"
    environment_variables += "\n        - name: APP_TIMEZONE\n          valueFrom:\n            configMapKeyRef:\n              name: egov-config\n              key: timezone"
    environment_variables += "\n        - name: JAVA_OPTS\n          value: \"{{{{conf['{}']['heap'] or '-Xmx64m -Xms64m'}}}}\"".format(service)
    environment_variables += "\n        - name: SPRING_JPA_SHOW_SQL\n          value: \"{{conf['egov-config']['spring-jpa-show-sql']}}\""
    environment_variables += "\n        - name: SERVER_PORT\n          value: \"8080\""
    environment_variables += "\n        - name: FLYWAY_ENABLED\n          value: \"false\""

    return environment_variables

def generate_manifest(app_properties_file, service, project_name):
    service_template = "service_template.yml"

    project_dir = Path("{}/{}",local_repo,project_name)
    db_folder = Path("{}/{}/src/main/resources/db".format(project_dir,service))
    is_db_folder_present = db_folder.is_dir()

    deployment_template = "deployment_template.yml"
    dockerfile_template = "dockerfile_template.yml"
    start_sh_template = "start_sh_template.yml"
    THIS_DIR = os.path.dirname(os.path.abspath(__file__))
    j2_env = Environment(loader=FileSystemLoader(THIS_DIR),trim_blocks=True)
    dockerfile = str(j2_env.get_template(dockerfile_template).render(service_name=service))
    start_sh = str(j2_env.get_template(start_sh_template).render(service_name=service))
    environment_variables = ""
    with open(app_properties_file) as f1:
        for line in nonblank_lines(f1):
            key, value = process_property(line)
            known_key = check_for_known_keys(key)
            if known_key is None:
                environment_variables += "\n        - name: " + key + "\n          value: " + value
            elif known_key == 1:
                continue
            else:
                value=check_for_known_keys(key)
                environment_variables += "\n        - name: " + key + "\n          " + value

    environment_variables=append_known_keys(environment_variables,service)
    manifest_file=Path("{}/cluster/app/egov/{}/{}.yml".format(infraops_repo,project_name,service))
    dockerfile_path=Path("{}/{}/{}/Dockerfile".format(local_repo,project_name,service))
    start_sh_path=Path("{}/{}/{}/start.sh".format(local_repo,project_name,service))

    k8s_manifest = str(j2_env.get_template(service_template).render(service_name=service, project=project_name))
    k8s_manifest += "\n" + str(j2_env.get_template(deployment_template).render(service_name=service, project=project_name, db_migration=is_db_folder_present,environment_variables=environment_variables, service_schema=process_key(service).lower()+ "_schema"))
    if manifest_file.is_file():
        print "\n\tWARN: {} manifest exists. I will still go ahead and create manifest at ./{}.yml".format(manifest_file, service)
        manifest_file = service + ".yml"
    f1 = open(str(dockerfile_path), "w")
    f1.write(dockerfile)
    print "\n\tINFO: Dockerfile {} has been written. ".format(dockerfile_path)
    f1.close()

    f2 = open(str(manifest_file), "w")
    f2.write(k8s_manifest)
    print "\n\tINFO: Manifest {} has been written. ".format(manifest_file)
    f2.close()
    f3 = open(str(start_sh_path), "w")
    f3.write(start_sh)
    print "\n\tINFO: Docker ENTRYPOINT file {} has been written. ".format(start_sh_path)
    f3.close()


def update_zuul_gateway(service):
    zuul_properties = local_repo + "/gateway/zuul/src/main/resources/application.properties"
    search_pattern = "zuul"
    with open(zuul_properties, "r+") as f:
        a = [x.rstrip() for x in f]
        index = 0
        for item in a:
            if item.startswith("zuul.sensitiveHeaders"):
                a.insert(index, "\nzuul.routes." + service + ".path=/" + service + "/**\nzuul.routes." + service + ".stripPrefix=false\nzuul.routes." + service + ".url=http://localhost:8084/\n".format(service))
                break
            index += 1
        f.seek(0)
        f.truncate()
        for line in a:
            f.write(line + "\n")
        print "\n\tINFO: Zuul gateway application properties {} has been updated. ".format(zuul_properties)

def update_zuul_manifest(service):
    zuul_manifest = infraops_repo + "/cluster/app/egov/gateway/zuul.yml"
    search_pattern = "- name: SERVER_PORT"
    with open(zuul_manifest, "rt") as fp:
        with open("/tmp/out.txt", "wt") as fout:
            for line in fp:
                fout.write(line.replace('- name: SERVER_PORT', "- name: ZUUL_ROUTES_" + process_key(service) + "_URL\n          value: http://" + service + ":8080/\n        - name: SERVER_PORT"))
    shutil.copy("/tmp/out.txt",zuul_manifest)
    print "\n\tINFO: Zuul kubernetes manifest {} has been updated. ".format(zuul_manifest)

def update_nginx_gateway(service):
    nginx_config = local_repo + "/gateway/nginx/nginx.conf"
    with open(nginx_config, "rt") as fp:
        with open("/tmp/out.txt", "wt") as fout:
            for line in fp:
                fout.write(line.replace('egov-idgen', 'egov-idgen|' + service))
    shutil.copy("/tmp/out.txt",nginx_config)
    print "\n\tINFO: Nginx configuration {} has been updated. \n".format(nginx_config)

def main():
    args = parse_args()
    validate_args(args)
    update_local_repo(local_repo)
    app_properties_file=validate_app_properties(args)
    if map_project_name(args.project) is not None:
        project_name = map_project_name(args.project)
    else:
        raise Exception("Invalid Project Name.")
    print "\n\n\tThis script will read application properties from {} and create necessary build/deploy configuration. \n\n\tYou may still need to do follwoing things manually. ".format(args.service)
    print "\n\t\t 1. Create docker repositories {} and {}-db".format(args.service,args.service)
    print "\n\t\t 2. Create jenkins build job {} under {}".format(args.service, args.project)
    print "\n\t\t 3. Manually look through {}.yml in InfraOps repo and remove unwanted properties. \n\t\t    It should only contain properties that needs to be overridden. \n\n\t\t    ex: db parameters (environment specific), kafka consumer id (can be edited by dev to test from beginning) etc".format(args.service)
    print "\n\t\t 4. You may also want to enable {} in dev/qa environments by adding in respective environment manifests".format(args.service)
    generate_manifest(app_properties_file, args.service, project_name)
    if args.gateway:
        update_zuul_gateway(args.service)
        update_nginx_gateway(args.service)
        update_zuul_manifest(args.service)

#TODO:
#Create docker repository
#Create jenkins job
#Update dev/qa environment manifest_file


def validate_args(args):
    if not args.service:
        print "microservice need to be specfied."
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
