#!/bin/bash

PERMISSION="write"

# get token to be able to talk to Docker Hub
TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${DOCKER_UNAME}'", "password": "'${DOCKER_UPASS}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token)

# get list of repos for that user account 
CURR_REPO_LIST=$(curl -s -H "Authorization: JWT ${TOKEN}" https://hub.docker.com/v2/repositories/${DOCKER_NAMESPACE}/ | jq -r '.results|.[]|.name')

CHK_REPO_LIST=${REPO_LIST//,/ }     

for i in $CHK_REPO_LIST; do 
 exists=                                                                                                                                                                  
 for j in $CURR_REPO_LIST; do                                                                                                                                                          
	if [ $i == $j ]; then                                                                                                                                                      
       exists=1                                                                                                                                                                
	    break                                                                                                                                                               
   fi                                                                                                                                                                 
 done                                                                                                                                                                
 if [ ! $exists ]; then                                                                                                                                                       
    CREATE_REPO_LIST="$CREATE_REPO_LIST $i"                                                                                                                                                           
 fi                                                                                                                                                                 
done                             
                                                                                                                                  
#Getting Group Id
GROUP_ID=$(curl -s -H "Authorization: JWT ${TOKEN}" https://hub.docker.com/v2/orgs/${DOCKER_NAMESPACE}/groups/${DOCKER_GROUP_NAME}/ | jq -r .id)

for REPO_NAME in ${CREATE_REPO_LIST}                                     
do                                                       
     #Create Repo
     CREATED_REPO=$(curl -s -H "Authorization: JWT ${TOKEN}" -H "Content-Type: application/json" -X POST -d '{"namespace":"'${DOCKER_NAMESPACE}'","name":"'${REPO_NAME}'","description":"","is_private":false,"full_description":""}' https://hub.docker.com/v2/repositories/ | jq -r .name)
     echo $CREATED_REPO " repository created"
     #Adding Permissions
     PERM_ADDED=$(curl -s -H "Authorization: JWT ${TOKEN}" -H "Content-Type: application/json" -X POST -d '{"group_id": "'${GROUP_ID}'", "groupid": "'${GROUP_ID}'", "group_name": "'${DOCKER_GROUP_NAME}'", "groupname": "'${DOCKER_GROUP_NAME}'", "permission": "'${PERMISSION}'"}' https://hub.docker.com/v2/repositories/${DOCKER_NAMESPACE}/${REPO_NAME}/groups/ | jq -r .group_name)
     echo $PERMISSION " permission to the group " $PERM_ADDED " for repository " $CREATED_REPO
done
