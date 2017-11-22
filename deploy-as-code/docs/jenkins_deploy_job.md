# Deploy a service

### Jenkins Job Structure
  - Each deploy job name should have the naming convention of deploy-to-<env>
  - Job takes two parameters service name and tag as inputs
  - Each job is a pipeline job with the following configurations
     - Name: deploy-to-<env>
     - Pipeline Definition: Pipeline script from SCM
     - Repository: <Git egov-InfraOps Repo URL>
     - ScriptPath: jenkins/pipelines/deployment
### Build Flow
 - Jenkins takes service name and docker tag from the user as input
 - deployer.groovy sets up kubernetes environment from Jenkins credentials. Following credentails should be available to the script
     - <env>-kube-ca
     - <env>-kube-cert
     - <env>-kube-key
     - <env>-kube-token #For token based auth only
     - <env>-kube-url
     - egov_secret_passcode  #Which was used to encrypt passwords in environment manifests
 - Groovy script then executes python script apply.py with the arguments env, service, docker_image:tag, docker_db_migration_image:tag
 - apply.py reads all arguments and renders following yaml's
     - namespaces.yml
     - configMaps.yml
     - secrets.yml
     - volumes.yml
     - <service_name>.yml
     ```console
     Note: apply.py uses Jinja2 to parse all environment specific variables from git:eGov-infraOps/cluster/conf/
     ```
 - apply.py executes "kubectl apply" using the parsed yaml's and prints STDOUT or STDERR.
