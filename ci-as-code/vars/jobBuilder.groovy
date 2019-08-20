import org.egov.jenkins.ConfigParser
import org.egov.jenkins.Utils
import org.egov.jenkins.models.JobConfig

library 'ci-libs'

def call(Map params) {
    git params.repo
    def yaml = readYaml file: params.configFile;
    List<String> folders = Utils.foldersToBeCreatedOrUpdated(yaml, env);
    List<JobConfig> jobConfigs = ConfigParser.populateConfigs(yaml.config);

    for( int i=0; i< folders.size(); i++ ){
        stage('Create folders') {
        container(name: 'jnlp') {
            jobDsl(scriptText: """
                folder("${folders[i]}")
                """
                )
        }     
        }
    }

    for(int i=0; i< jobConfigs.size(); i++){
        stage('Create jobs') {
        container(name: 'jnlp') {
            jobDsl(scriptText: """
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
"""
                )
        }          
        }

    }

}
