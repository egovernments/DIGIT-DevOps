
FROM golang:1.13-alpine as build

ENV GO111MODULE=on
ENV GOCACHE=/tmp

ARG WORK_DIR
WORKDIR /app

COPY ${WORK_DIR}/go.mod .
COPY ${WORK_DIR}/go.sum .

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build


# Create runtime image
FROM alpine:3

ARG KUBECTL_VERSION=v1.12.10
ARG SOPS_VERSION=v3.5.0

WORKDIR /opt/egov

RUN addgroup -S egov && adduser -S -G egov egov 
COPY --chown=egov:egov --from=build /app/egov-deployer /opt/egov/

RUN chmod +x /opt/egov/egov-deployer 
RUN wget https://storage.googleapis.com/kubernetes-release/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl \
    && wget -O aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.12.7/2019-03-27/bin/linux/amd64/aws-iam-authenticator \
    && wget -O sops https://github.com/mozilla/sops/releases/download/$SOPS_VERSION/sops-$SOPS_VERSION.linux \
    && chmod +x ./kubectl ./aws-iam-authenticator ./sops \
    && mv ./kubectl ./aws-iam-authenticator ./sops /usr/local/bin 

USER egov