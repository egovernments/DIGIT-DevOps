# Jenkins Build Jobs

### Job Structure
- Each project should have a folder which holds all build jobs for it's micro-services
- Folder name should be the project name. ex: asset, hr, core, web
- Job name should be the service name. ex: egf-masters, asset-indexer
- Each job is a pipeline job with the following configurations
- Name: <Service Name>
- Poll SCM: H/10 * * * *   # Job will poll git every 10 minutes
- Pipeline Definition: Pipeline script from SCM
- SCM: Git
- Repository URL: <Git eGov-services Repo URL>
- Included Regions: <module>/<service name>   # as in Jenkins folder and Jobname
- ScriptPath: Jenkinsfile
- Sparse checkout path:
	1. /Jenkinsfile
    2. /jenkins
    3. /build.sh
    4. /project/service\-name

## Build Flow
 - During build, Groovy script (Jenkinsfile) from root of the repo is called by Jenkins
 - Script will force run the build on slave server
  Build has five stages
    ### 1. Build :
     - Script checks for build.wkflo existence in repo for this service. If exists, follow the workflow defined in it.
     - Else runs default build instructions from build.sh
     - build.sh brings up CI container which has necessary pre-installed software and run maven build inside the container.
    ### 2. Archive Results:
     - Jenkins then archives the generated artifacts within Jenkins
    ### 3. Build Docker Image
     - Groovy script Jenkinsfile uses the Dockerfile found in <project>/<service_name> to build the docker image.
     - It also checks for the existence of Dockerfile inside <project>/<service_name>/src/main/resources/db/Dockerfile to identify db migration
     - If db migration is found, it builds the docker image using the Dockerfile for db migration.
     - These images are tagged as egovio/<service_name>:<Jenkins_Job_ID>-<Git_Commit_Hash> and egovio/<service_name>:latest
    ### 4. Publish Docker Image
     - Script then pushes all images found in the host to docker hub.
    ### 5. Clean Docker Images
     -  deletes all the docker images from the host.

### Error Notification
  In case if any of the stage has failed, it will trigger notification stage
   - A Slack notification is send to #pgr-notification channel with Build URL
   - An email is sent to All developers who has committed from the last successful build, last committed developers and micro-devs@egovernments.org
