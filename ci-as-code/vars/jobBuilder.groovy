import org.egov.jenkins.ConfigParser
import org.egov.jenkins.Utils
import org.egov.jenkins.models.JobConfig

def call(Map params) {
    node {
        git params.repo
        def yaml = readYaml file: params.configFile;
        List<String> folders = Utils.foldersToBeCreatedOrUpdated(yaml, env);
        List<Object> jobConfigMap = yaml.config
        List<JobConfig> jobConfigs = ConfigParser.populateConfigs(jobConfigMap, env);

        StringBuilder jobDslScript = new StringBuilder();

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
                                remote {url("${params.repo}")} 
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

        jobDsl scriptText: jobDslScript.toString()

    }

}
