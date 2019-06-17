az login
az account set --subscription="${SUBSCRIPTION_ID}"
az account show --query "{subscriptionId:id, tenantId:tenantId}"
az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}"


To test your credentials, open a new shell and run the following command, using the returned values for sp_name, password, and tenant:

az login --service-principal -u SP_NAME -p PASSWORD --tenant TENANT
az vm list-sizes --location westus
