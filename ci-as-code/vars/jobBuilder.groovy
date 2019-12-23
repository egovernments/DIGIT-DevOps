import org.egov.jenkins.ConfigParser
import org.egov.jenkins.Utils
import org.egov.jenkins.models.JobConfig
import org.egov.jenkins.models.BuildConfig

def call(Map params) {

    podTemplate(yaml: """
        kind: Pod
        metadata:
        name: build-utils
        spec:
        containers:
        - name: build-utils
            image: egovio/build-utils
            imagePullPolicy: IfNotPresent
            env:
            - name: DOCKER_UNAME
              valueFrom:
                  secretKeyRef:
                    name: docker-credentials
                    key: docker_uname
            - name: DOCKER_UPASS
              valueFrom:
                  secretKeyRef:
                    name: docker-credentials
                    key: docker_upass
            - name: DOCKER_NAMESPACE
                value: egovio
            - name: DOCKER_GROUP_NAME
                value: dev     
            resources:
            requests:
                memory: "768Mi"
                cpu: "250m"
            limits:
                memory: "1024Mi"
                cpu: "500m"                
        """
    )

    node(POD_LABEL) {
        
        List<String> gitUrls = params.urls;
        String configFile = './build/build-config.yml';
        Map<String,List<JobConfig>> jobConfigMap=new HashMap<>();

        for (int i = 0; i < gitUrls.size(); i++) {
            String dirName = Utils.getDirName(gitUrls[i]);
            dir(dirName) {
                 git url: gitUrls[i], credentialsId: 'git_read'
                 def yaml = readYaml file: configFile;
                 List<JobConfig> jobConfigs = ConfigParser.populateConfigs(yaml.config, env);
                 jobConfigMap.put(gitUrls[i],jobConfigs);
            }
        }

        StringBuilder jobDslScript = new StringBuilder();
        StringBuilder repoList = new StringBuilder();

        for (Map.Entry<Integer, String> entry : jobConfigMap.entrySet()) {   

            List<JobConfig> jobConfigs = entry.getValue();
 
            List<String> folders = Utils.foldersToBeCreatedOrUpdated(jobConfigs, env);

            for (int i = 0; i < folders.size(); i++) {
                jobDslScript.append("""
                    folder("${folders[i]}")
                    """);
              }

        for (int i = 0; i < jobConfigs.size(); i++) {

            for(int j=0; j<jobConfigs.getBuildConfigs().size(); j++){
                BuildConfig buildConfig = jobConfig.getBuildConfigs().get(j);
                repoList.append(buildConfig.getImageName());
                    if(j!=jobConfigs.getBuildConfigs().size()-1)
                    {
                        repoList.append(",");
                    }
            }

            jobDslScript.append("""
            pipelineJob("${jobConfigs.get(i).getName()}") {
                logRotator(-1, 5, -1, -1)
                parameters {
                  gitParameterDefinition {
                        name('BRANCH')
                        type('BRANCH')
                        description('') 
                        branch('')      
                        useRepository('')                     
                        defaultValue('origin/master') 
                        branchFilter('.*')
                        tagFilter('*')
                        sortMode('ASCENDING_SMART')
                        selectedValue('DEFAULT')
                        quickFilterEnabled(true)
                        listSize('5')                 
                  }
                }
                definition {
                    cpsScm {
                        scm {
                            git{
                                remote {
                                    url("${entry.getKey()}")
                                    credentials('git_read')
                                } 
                                branch ('\${BRANCH}')
                                scriptPath('Jenkinsfile')
                                extensions { }
                            }
                        }

                    }
                }
            }
""");
        }
        }

        stage('Building jobs') {
            sh """ 
            echo ${jobDslScript.toString()}
            """
          // jobDsl scriptText: jobDslScript.toString()
        }

        stage('Creating Repositories in DockerHub') {
                    withEnv(["REPO_LIST=${repoList.toString()}"
                    ]) {
                        container(name: 'build-utils', shell: '/bin/sh') {
                           // sh (script:'sh /tmp/scripts/create_repo.sh')
                           sh (script:'echo \$REPO_LIST')
                        }
                    }
        }
                

    }

}
