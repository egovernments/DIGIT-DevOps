
FROM golang:1.13-alpine as build

ENV GO111MODULE=on

ARG WORK_DIR
WORKDIR /app

COPY ${WORK_DIR}/go.mod .
COPY ${WORK_DIR}/go.sum .

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build


# Create runtime image
FROM alpine:3

WORKDIR /opt/egov

RUN addgroup -S egov && adduser -S -G egov egov 
COPY --chown=egov:egov --from=build /app/egov-deployer /opt/egov/

RUN chmod +x /opt/egov/egov-deployer 
RUN apk add curl --update \
    && mkdir -p /home/egov/.kube \
    && chmod -R 777 /home/egov/.kube \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.12.10/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.12.7/2019-03-27/bin/linux/amd64/aws-iam-authenticator \
    && chmod +x ./aws-iam-authenticator \
    && mv ./aws-iam-authenticator /usr/local/bin/aws-iam-authenticator 

USER egov