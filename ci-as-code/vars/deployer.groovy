library 'ci-libs'

def call(Map pipelinepipelineParams) {
    podTemplate(yaml: """
kind: Pod
metadata:
  name: egov-deployer
spec:
  containers:
  - name: egov-deployer
    image: egovio/egov-deployer
    command:
    - /busybox/cat
    tty: true
    env:  
      - name: "GOOGLE_APPLICATION_CREDENTIALS"
        value: "/var/run/secret/cloud.google.com/service-account.json"            
    volumeMounts:
      - name: service-account
        mountPath: /var/run/secret/cloud.google.com
      - name: kube-config
        mountPath: /home/egov/.kube     
    resources:
      requests:
        memory: "256Mi"
        cpu: "200m"
      limits:
        memory: "256Mi"
        cpu: "200m"  
  volumes:
  - name: service-account
    secret:
        secretName: "gcp-kms-decryptor-sa"    
  - name: kube-config
    secret:
        secretName: '${pipelineParams.environment}-kube-config'                    
"""
    ) {
        node(POD_LABEL) {
                stage('Deploy Images') {
                        container(name: 'egov-deployer', shell: '/bin/sh') {
                            sh (script:
                                    './egov-deployer deploy -e ${pipelineParams.environment} ${env.IMAGES}'
                        }
                }
        }
    }

}
