

`export KUBECONFIG=~/path/to/config`

**Setup cluster on minikube**

Install minikube - https://github.com/kubernetes/minikube

Install kubectl - https://kubernetes.io/docs/user-guide/prereqs/

Create namespaces -
    `kubectl -f cluster/egov-namespaces.yml`

To create a service/deployment in backbone namespace - `kubectl -f cluster/backbone `

To create a service/deployment in common namespace - `kubectl -f cluster/common`

To create a service/deployment in a module namespace - `kubectl -f cluster/<module>`
Ex - For pgr - `kubectl -f cluster/pgr`


**Deploying a new container to the cluster**

To deploy a new container to a deployment of rest service of version 1.1 in pgr namespace,

`kubectl set image deployment/rest rest=egovio/pgrrest:1.1 --namespace=pgr`

To check the status of deployment

`kubectl rollout status deployment/rest --namespace=pgr`

To check the deployment history

`kubectl rollout history deployment/rest --namespace=pgr`

To revert a deployment to previous revision

`kubectl rollout undo deployment/rest --namespace=pgr`

To revert a deployment to a particular revision

`kubectl rollout undo deployment/rest --namespace=pgr --to-revision=2`
