deployer_image = "egovio/deployer:1.0.0"

def takeSnapshot(group, env){
    stage("Snapshot ${env} env"){
        def cmd = "python scripts/snapshot.py ${group}"
        run(env, cmd)
    }
}

def deploy(env){
    stage("Deploy to ${env} env"){
        def cmd = "python scripts/deploy.py ${env}"
        run(env, cmd)
    }
}

def deployStandAlone(env, service, image, tag){
    stage("Deploy to ${env} env"){
        def cmd = "python scripts/apply.py  -e ${env} -m ${service} -i egovio/${image}:${tag} -dmi egovio/${image}-db:${tag} -conf -secret"
        run(env, cmd)
    }
}

def run(env, cmd){
    docker.image("${deployer_image}").inside {
        if (env == "pbuatv2") {
            set_kube_config(env)
            
            withCredentials([
                string(credentialsId: "${env}-aws-access-key", variable: "AWS_ACCESS_KEY"),
                string(credentialsId: "${env}-aws-secret-access-key", variable: "AWS_SECRET_ACCESS_KEY"),
                string(credentialsId: "${env}-aws-region", variable: "AWS_REGION"),
                string(credentialsId: "egov_secret_passcode", variable: "EGOV_SECRET_PASSCODE")
            ]){
                sh cmd;
            }
            
        } else{
            set_kube_credentials(env)
            withCredentials([
                string(credentialsId: "${env}-kube-url", variable: "KUBE_SERVER_URL"),
                string(credentialsId: "egov_secret_passcode", variable: "EGOV_SECRET_PASSCODE")
            ]){
                sh "kubectl config set-cluster env --server ${KUBE_SERVER_URL}"
                sh cmd;
            }
        }
    }
}

def set_kube_credentials(env){
    withCredentials([
        file(credentialsId: "${env}-kube-ca", variable: "CA"),
        file(credentialsId: "${env}-kube-cert", variable: "CERT"),
        file(credentialsId: "${env}-kube-key", variable: "CERT_KEY")
    ]){
        sh "cp ${CA} /kube/ca.pem"
        sh "cp ${CERT} /kube/admin.pem"
        sh "cp ${CERT_KEY} /kube/admin-key.pem"
    }

    if (env == "apUat" || env == "apProd" || env == "playground" || env == "qa" || env == "ukd-uat") {
        withCredentials([string(credentialsId: "${env}-kube-token", variable: "TOKEN")]){
            sh "kubectl config set-credentials env --token ${TOKEN}"
        }
    }

    if (env == "pbuat" || env == "pbprod" || env=="dev" || env =="demoenv2") {
        withCredentials([string(credentialsId: "${env}-kube-username", variable: "AUTHUSER")]){
            sh "kubectl config set-credentials env --username=${AUTHUSER}"
        }
        withCredentials([string(credentialsId: "${env}-kube-password", variable: "AUTHPASSWORD")]){
            sh "kubectl config set-credentials env --password=${AUTHPASSWORD}"
        }
    }

}

def set_kube_config(env){
    withCredentials([file(credentialsId: "${env}-kube-config", variable: "KUBE_CONFIG")]){
        sh "cp ${KUBE_CONFIG} /.kube/config"
    }

}

return this;
