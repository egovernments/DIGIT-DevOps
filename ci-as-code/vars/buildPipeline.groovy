import org.egov.jenkins.ConfigParser
import org.egov.jenkins.models.BuildConfig
import org.egov.jenkins.models.JobConfig

import static org.egov.jenkins.ConfigParser.getCommonBasePath

library 'ci-libs'

def call(Map pipelineParams) {
    podTemplate(yaml: """
kind: Pod
metadata:
  name: kaniko
spec:
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    imagePullPolicy: IfNotPresent
    command:
    - /busybox/cat
    tty: true
    volumeMounts:
      - name: jenkins-docker-cfg
        mountPath: /root
      - name: kaniko-cache
        mountPath: /cache  
    resources:
      requests:
        memory: "1280Mi"
        cpu: "750m"
      limits:
        memory: "2048Mi"
        cpu: "1250m"      
  - name: git
    image: docker.io/nithindv/alpine-git:latest
    imagePullPolicy: IfNotPresent
    command:
    - cat
    tty: true        
  volumes:
  - name: kaniko-cache
    persistentVolumeClaim:
      claimName: kaniko-cache-claim
      readOnly: true      
  - name: jenkins-docker-cfg
    projected:
      sources:
      - secret:
          name: regcred-self
          items:
            - key: .dockerconfigjson
              path: .docker/config.json             
"""
    ) {
        node(POD_LABEL) {

            def scmVars = checkout scm
            final String REPO_NAME = "docker.io/nithindv";
            def yaml = readYaml file: pipelineParams.configFile;
            List<JobConfig> jobConfigs = ConfigParser.parseConfig(yaml, env);

            for(int i=0; i<jobConfigs.size(); i++){
                JobConfig jobConfig = jobConfigs.get(i)

                stage('Parse Latest Git Commit') {
                    withEnv(["BUILD_PATH=${jobConfig.getBuildConfigs().get(0).getWorkDir()}",
                             "PATH=alpine:$PATH"
                    ]) {
                        container(name: 'git', shell: '/bin/sh') {
                            scmVars['ACTUAL_COMMIT'] = sh (script:
                                    'git log --oneline -- ${BUILD_PATH} | awk \'NR==1{print $1}\'',
                                    returnStdout: true).trim()
                            scmVars['BRANCH'] = scmVars['GIT_BRANCH'].replaceFirst("origin/", "")
                        }
                    }
                }

                stage('Build with Kaniko') {
                    withEnv(["PATH=/busybox:/kaniko:$PATH"
                    ]) {
                        container(name: 'kaniko', shell: '/busybox/sh') {

                            for(int j=0; j<jobConfig.getBuildConfigs().size(); j++){
                                BuildConfig buildConfig = jobConfig.getBuildConfigs().get(j)
                                if( ! fileExists(buildConfig.getWorkDir()) || ! fileExists(buildConfig.getDockerFile()))
                                    throw new Exception("Working directory / dockerfile does not exist!");

                                String workDir = buildConfig.getWorkDir().replaceFirst(getCommonBasePath(buildConfig.getWorkDir(), buildConfig.getDockerFile()), "./")
                                String image = "${REPO_NAME}/${buildConfig.getImageName()}:${env.BUILD_NUMBER}-${scmVars.BRANCH}-${scmVars.ACTUAL_COMMIT}";
                                sh """
                                    echo \"Attempting to build image,  ${image}\"
                                    /kaniko/executor -f `pwd`/${buildConfig.getDockerFile()} -c `pwd`/${buildConfig.getContext()} \
                                    --build-arg WORK_DIR=${workDir} \
                                    --cache=true --cache-dir=/cache \
                                    --single-snapshot=true \
                                    --snapshotMode=time \
                                    --destination=${image} \
                                    --no-push=true --cache-repo=egovio/cache/cache
                                """

                            }
                        }
                    }
                }
            }


        }
    }

}
