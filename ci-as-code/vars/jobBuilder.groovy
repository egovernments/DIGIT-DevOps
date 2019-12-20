import org.egov.jenkins.ConfigParser
import org.egov.jenkins.Utils
import org.egov.jenkins.models.JobConfig

def call(Map params) {
    node {
        
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

        for (Map.Entry<Integer, String> entry : jobConfigMap.entrySet()) {   

            List<JobConfig> jobConfigs = entry.getValue();
            List<String> folders = Utils.foldersToBeCreatedOrUpdated(jobConfigs, env);

            for (int i = 0; i < folders.size(); i++) {
                jobDslScript.append("""
                    folder("${folders[i]}")
                    """);
              }

        for (int i = 0; i < jobConfigs.size(); i++) {
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
          //  jobDsl scriptText: jobDslScript.toString()
        }

    }

}
