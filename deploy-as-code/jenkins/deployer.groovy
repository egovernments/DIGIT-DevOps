deployer_image = "egovio/deployer:0.0.2"

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
        set_kube_credentials(env)
        withCredentials([string(credentialsId: "${env}-kube-url", variable: "KUBE_SERVER_URL")]){
            sh "kubectl config set-cluster env --server ${KUBE_SERVER_URL}"
        }
        withCredentials([string(credentialsId: "egov_secret_passcode", variable: "EGOV_SECRET_PASSCODE")]) {
            sh cmd;
        }
    }
}

def set_kube_credentials(env){
    withCredentials([file(credentialsId: "${env}-kube-ca", variable: "CA")]){
        sh "cp ${CA} /kube/ca.pem"
    }
    withCredentials([file(credentialsId: "${env}-kube-cert", variable: "CERT")]){
        sh "cp ${CERT} /kube/admin.pem"
    }
    withCredentials([file(credentialsId: "${env}-kube-key", variable: "CERT_KEY")]){
        sh "cp ${CERT_KEY} /kube/admin-key.pem"
    }

    if (env == "apUat" || env == "apProd") {
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

return this;
