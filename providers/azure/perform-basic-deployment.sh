perform-basic-build() {
	# set the default location
	az configure --defaults location=${V4_CFG_CLOUD_PROVIDER_LOCATION}

	az group create --name ${V4_CFG_TARGET_RESOURCE_GROUP} --location ${V4_CFG_CLOUD_PROVIDER_LOCATION} >>"${LOG_FILE}"

	az configure --defaults group="${V4_CFG_TARGET_RESOURCE_GROUP}"

	create-vnet

	log-message "Configuring DNS Zone: ${V4_CFG_DNS_ZONE}"
	configure-dns-zone

	log-message "Creating service principal for AKS..."
	export SP_INFO=$(az ad sp create-for-rbac --name "http://${V4_CFG_DEPLOY_PREFIX}-${V4_CFG_TARGET_RESOURCE_GROUP}-${V4_CFG_CLOUD_PROVIDER_LOCATION}" --skip-assignment)
	log-message "Sleeping 30 seconds to allow principal to propagate through AAD infrastructure..."
	sleep 30
	SP_EXISTS=$( az ad sp list --display-name ${V4_CFG_DEPLOY_PREFIX}-${V4_CFG_TARGET_RESOURCE_GROUP}-${V4_CFG_CLOUD_PROVIDER_LOCATION} --query '[].displayName'  -o tsv )
	until [[ "${SP_EXISTS}" = "${V4_CFG_DEPLOY_PREFIX}-${V4_CFG_TARGET_RESOURCE_GROUP}-${V4_CFG_CLOUD_PROVIDER_LOCATION}" ]] ; do
		log-message "Service principal query has not yet been successful.  Will try again in 30 seconds."
		sleep 30
		SP_EXISTS=$( az ad sp list --display-name ${V4_CFG_DEPLOY_PREFIX}-${V4_CFG_TARGET_RESOURCE_GROUP}-${V4_CFG_CLOUD_PROVIDER_LOCATION} --query '[].displayName'  -o tsv )
	done

	export V4_CFG_CLOUD_PROVIDER_SP_APP_ID=$(echo "$SP_INFO" | grep appId | cut -d: -f2 | tr -d '",[:blank:]')
	export SP_PWD=$(echo "$SP_INFO" | grep password | cut -d: -f2 | tr -d '",[:blank:]')

	log-message "Created Service Principal / aad appId: ${V4_CFG_CLOUD_PROVIDER_SP_APP_ID}"

	log-message "Adding Network Contributor role to the service principal..."
	export VNET_ID=$(az network vnet show --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --name ${VNET_NAME} --query id -o tsv)
	export SUBNET_ID=$(az network vnet subnet show --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --vnet-name "${VNET_NAME}" --name "${VNET_NAME}-aks-subnet" --query id -o tsv)

	az role assignment create --assignee ${V4_CFG_CLOUD_PROVIDER_SP_APP_ID} --scope ${VNET_ID} --role "Network Contributor" >>"${LOG_FILE}"

	setup-nfs-server &
	setup-postgres-server &

	wait

	# Collect and set variables adjusted in subprocesses
	#set-variables-from-subtask "setup-aks-cluster"
	set-variables-from-subtask "setup-postgres-server"
	set-variables-from-subtask "setup-nfs-server"

	setup-aks-cluster 

	# clear the default group set earlier in script
	az configure --defaults group=""

}

perform-basic-deployment() {

	#####
	# SAS deployment:
	# - Download the latest Kustomize manifests for the order
	# - Tailor the deployment for this environment
	# - Run Kustomize
	# - Deploy
	#####
	cd "${DEPLOYMENT_DIR}"
	prep-and-run-kustomize

	# Set INSTALL_VIYA to true if it is unset
	INSTALL_VIYA=${INSTALL_VIYA:-true}
    log-message "the value of INSTALL_VIYA is : ${INSTALL_VIYA}"
	if [[ "${INSTALL_VIYA}" = "true" ]] ; then
		kubectl apply -n ${V4_CFG_K8S_TARGET_NAMESPACE} -f base.yaml | tee -a "${LOG_FILE}"

		# poll for ready needs some more work to be reliable..  For now just end.
		#poll-for-ready | tee -a "${LOG_FILE}"
	else
		log-message "INSTALL_VIYA = false.  Will not install."
	fi

	#####
	#
	# To enable the K8s dashboard execute the following
	# kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
	#
	# Then to launch the K8s dashboard issue this command:
	# az aks browse --resource-group $V4_CFG_TARGET_RESOURCE_GROUP --name $V4_CFG_K8S_CLUSTER_NAME
	#
	#####

}
