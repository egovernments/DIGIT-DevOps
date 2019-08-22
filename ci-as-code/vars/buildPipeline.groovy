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
      - name: kaniko-cache
        mountPath: /cache        
  - name: git
    image: docker.io/nithindv/alpine-git:latest
    imagePullPolicy: Always
    command:
    - cat
    tty: true        
  volumes:
  - name: kaniko-cache
    persistentVolumeClaim:
      claimName: kaniko-cache-claim
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
            final String REPO_NAME = "docker.io/nithindv";
            def yaml = readYaml file: pipelineParams.configFile;
            List<JobConfig> jobConfigs = ConfigParser.parseConfig(yaml, env);

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

                stage('Build with Kaniko') {
                    withEnv(["PATH=/busybox:/kaniko:$PATH"
                    ]) {
                        StringBuilder script = new StringBuilder("#!/busybox/sh");

                        jobConfig.getBuildConfigs().each { buildConfig ->
                            String image = "${REPO_NAME}/${buildConfig.getImageName()}:${env.BUILD_NUMBER}-${readFile('commit').trim()}";
                            script.append("""
                whoami
                echo \"Attempting to build image,  ${image}\"
                /kaniko/executor -f `pwd`/${buildConfig.getDockerFile()} -c `pwd`/${buildConfig.getContext()} \
                --build-arg WORK_DIR=${buildConfig.getWorkDir()} \
                --cache=true --cache-repo=${REPO_NAME}/kaniko-cache \
                --destination=${image}
                        """)

                        }


                        container(name: 'kaniko', shell: '/busybox/sh') {
                            sh script.toString();
                        }
                    }
                }
            }


        }
    }

}