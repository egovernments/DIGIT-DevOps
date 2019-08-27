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
    resources:
      requests:
        memory: "704Mi"
        cpu: "500m"
      limits:
        memory: "1Gi"
        cpu: "1000m"      
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

            jobConfigs.each { jobConfig ->

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
                        StringBuilder script = new StringBuilder("#!/busybox/sh");

                        jobConfig.getBuildConfigs().each { buildConfig ->
                            String image = "${REPO_NAME}/${buildConfig.getImageName()}:${env.BUILD_NUMBER}-${scmVars.BRANCH}-${scmVars.ACTUAL_COMMIT}";
                            script.append("""
                echo \"Attempting to build image,  ${image}\"
                /kaniko/executor -f `pwd`/${buildConfig.getDockerFile()} -c `pwd`/${buildConfig.getContext()} \
                --build-arg WORK_DIR=${buildConfig.getWorkDir()} \
                --cache=true --cache-dir=/cache --single-snapshot \
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
