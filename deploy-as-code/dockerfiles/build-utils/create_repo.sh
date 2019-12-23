#!/bin/bash

PERMISSION="write"

# get token to be able to talk to Docker Hub
TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${DOCKER_UNAME}'", "password": "'${DOCKER_UPASS}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token)

NEXT_PAGE="https://hub.docker.com/v2/repositories/${DOCKER_NAMESPACE}/?page_size=100"
#Check if next page availiable if so get curl it and append the repositories to curr_repo_list                                                                                                                   
while [ $NEXT_PAGE != null ]                                                                             
do                                                                                                                                                                  
# get list of repos for that user account                                                                                                                      
JSON_VALUE=$(curl -s -H "Authorization: JWT ${TOKEN}" $NEXT_PAGE)                                                                     
CURR_REPO_LIST="$CURR_REPO_LIST $(echo "$JSON_VALUE" | jq -r '.results|.[]|.name')"                                                   
NEXT_PAGE=$(echo "$JSON_VALUE" | jq -r '.next')                                                                                       
done

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
if [[ "$CREATE_REPO_LIST" == null || "$CREATE_REPO_LIST" == "" ]]; then                                                                                                                                  
   echo "Repositories already exists"
 else
    #Getting Group Id
   GROUP_ID=$(curl -s -H "Authorization: JWT ${TOKEN}" https://hub.docker.com/v2/orgs/${DOCKER_NAMESPACE}/groups/${DOCKER_GROUP_NAME}/ | jq -r .id)

   for REPO_NAME in ${CREATE_REPO_LIST}                                     
   do                                                       
      #Create Repo
      REPO_RESPONSE_JSON=$(curl -s -H "Authorization: JWT ${TOKEN}" -H "Content-Type: application/json" -X POST -d '{"namespace":"'${DOCKER_NAMESPACE}'","name":"'${REPO_NAME}'","description":"","is_private":false,"full_description":""}' https://hub.docker.com/v2/repositories/)
      CREATED_REPO=$(echo "$REPO_RESPONSE_JSON" | jq -r '.name')
      if [ "$CREATED_REPO" == null ]; then
        echo $REPO_RESPONSE_JSON
       else
        echo $CREATED_REPO "repository created"
      fi
      #Adding Permissions
      PERM_RESPONSE_JSON=$(curl -s -H "Authorization: JWT ${TOKEN}" -H "Content-Type: application/json" -X POST -d '{"group_id": "'${GROUP_ID}'", "groupid": "'${GROUP_ID}'", "group_name": "'${DOCKER_GROUP_NAME}'", "groupname": "'${DOCKER_GROUP_NAME}'", "permission": "'${PERMISSION}'"}' https://hub.docker.com/v2/repositories/${DOCKER_NAMESPACE}/${REPO_NAME}/groups/)
      PERM_ADDED=$(echo "$PERM_RESPONSE_JSON" | jq -r '.group_name')
      if [ "$PERM_ADDED" == null ]; then
        echo $PERM_RESPONSE_JSON
       else
        echo $PERMISSION "permission added to the group" $PERM_ADDED "id" $GROUP_ID "for repository" $CREATED_REPO
      fi
   done
fi