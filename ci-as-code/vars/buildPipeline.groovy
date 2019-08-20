import org.egov.jenkins.ConfigParser
import org.egov.jenkins.models.JobConfig

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
    imagePullPolicy: Always
    command:
    - /busybox/cat
    tty: true
    volumeMounts:
      - name: jenkins-docker-cfg
        mountPath: /root
  - name: git
    image: docker.io/nithindv/alpine-git:latest
    imagePullPolicy: Always
    command:
    - cat
    tty: true        
  volumes:
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

            checkout scm
            def yaml = readYaml file: pipelineParams.configFile;
            List<JobConfig> jobConfigs = ConfigParser.parseConfig(yaml, env);
//            JobConfig jobConfig = jobConfigs.get(0);

            jobConfigs.each { jobConfig ->

                stage('Parse Latest Git Commit') {
                    withEnv(["BUILD_PATH=${jobConfig.getBuildConfigs().get(0).getContext()}",
                             "PATH=alpine:$PATH"
                    ]) {
                        container(name: 'git', shell: '/bin/sh') {
                            sh '''#!/bin/sh
                  git log --oneline -- ${BUILD_PATH} | awk \'NR==1{print $1}\' > commit
                  '''
                        }
                    }
                }
                jobConfig.getBuildConfigs().each { buildConfig ->
                    stage('Build with Kaniko') {
                        withEnv(["BUILD_PATH=${buildConfig.getContext()}",
                                 "PATH=/busybox:/kaniko:$PATH",
                                 "REPO_NAME=docker.io/nithindv",
                                 "BUILD_NUMBER=${env.BUILD_NUMBER}",
                                 "IMAGE_NAME=${buildConfig.getImageName()}",
                                 "COMMIT_HASH=${readFile('commit').trim()}"
                        ]) {
                            container(name: 'kaniko', shell: '/busybox/sh') {
                                sh '''#!/busybox/sh
                echo "Attempting to build image,  ${REPO_NAME}/${IMAGE_NAME}:${BUILD_NUMBER}-${COMMIT_HASH}"
                        /kaniko/executor -f `pwd`/${BUILD_PATH}/Dockerfile -c `pwd`/${BUILD_PATH} \
                --cache=true \
                --destination=${REPO_NAME}/${IMAGE_NAME}:${BUILD_NUMBER}-${COMMIT_HASH}
                        '''
                            }
                        }
                    }
                }
            }


        }
    }

}