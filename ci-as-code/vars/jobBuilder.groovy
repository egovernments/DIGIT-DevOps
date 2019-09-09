import org.egov.jenkins.ConfigParser
import org.egov.jenkins.Utils
import org.egov.jenkins.models.JobConfig

def call(Map params) {
    node {
        git url: params.repo, credentialsId: 'git_read'
        def yaml = readYaml file: params.configFile;
        List<JobConfig> jobConfigs = ConfigParser.populateConfigs(yaml.config, env);
        List<String> folders = Utils.foldersToBeCreatedOrUpdated(jobConfigs, env);

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
                                remote {
                                    url("${params.repo}")
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

        stage('Building jobs') {
            jobDsl scriptText: jobDslScript.toString()
        }

    }

}
