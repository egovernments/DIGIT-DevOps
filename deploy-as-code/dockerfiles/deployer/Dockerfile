FROM python:2

ADD kubeconfig /.kube/config
COPY requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt \
    && mkdir -p /.kube \
    && mkdir -p /kube \
    && chmod 777 /kube \
    && chmod -R 777 /.kube \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.12.10/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.12.7/2019-03-27/bin/linux/amd64/aws-iam-authenticator \
    && chmod +x ./aws-iam-authenticator \
    && mv ./aws-iam-authenticator /usr/local/bin/aws-iam-authenticator 