declare -A VM_CORES
declare -A VM_RAM
declare -A VM_MAX_DISK_COUNT
declare -A VM_EPHEMERAL_DISK_SIZE
declare -A VM_OS_DISK_SIZE

declare -A RESOURCE_USAGE_CURRENT
declare -A RESOURCE_USAGE_LIMIT

validate-environment() {

	AZ_EXE=$(which az) || {
		echo
		echo "ERROR: The Azure CLI is not installed or is not on the path."
		echo "       Ensure that the Azure CLI is installed and on your path"
		echo "       see https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest"
		exit 1
	}

    if FOO=$(az ad signed-in-user show)
	then
		echo "NOTE: User is signed in with the Azure CLI"
	else
		while [[ "${FOO}" = "" ]] ; do
			# we are not logged in or do not have access to any accounts
			echo "You must login to your azure account.  The script will invoke az login for you.  "
			echo "Follow any instructions presented by az login and switch back to this window once logged on."
			read -n 1 -s -r -p "Press any key to continue"
			FOO=$(az login)
		done
	fi
}

validate-account() {
	V4_CFG_CLOUD_PROVIDER_ACCOUNT_IS_VALID=$(az account list --query '[].{Name: name, ID: id}' -o tsv | grep "${V4_CFG_CLOUD_PROVIDER_ACCOUNT}" )
	if [[ "${V4_CFG_CLOUD_PROVIDER_ACCOUNT_IS_VALID}" = "" ]]; then
		echo "ERROR: The specified account ${V4_CFG_CLOUD_PROVIDER_ACCOUNT} does not appear in your list of authorized accounts."
		exit 1
	else
		az account set --subscription "${V4_CFG_CLOUD_PROVIDER_ACCOUNT}" || {
			echo
			echo "ERROR: Subscription is not valid or not signed in."
			echo "       Ensure the subscription name is valid and you are logged in"
			echo "       before attempting to deploy."
			echo "       see https://docs.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest"
			echo "       and https://docs.microsoft.com/en-us/cli/azure/account?view=azure-cli-latest#az-account-list"
			exit 1
	}
	fi
}

validate-location() {
	LOCATION_VALID=$( az account list-locations --query '[].{Name: name}' -o tsv | grep "${V4_CFG_CLOUD_PROVIDER_LOCATION}" )
	if [[ "${LOCATION_VALID}" != "" ]] ; then
		log-message "The requested location (${V4_CFG_CLOUD_PROVIDER_LOCATION}) is valid."
	else 
		export V4_CFG_REQUESTED_CONFIG_IS_VALID="false"
		log-message "The requested location (${V4_CFG_CLOUD_PROVIDER_LOCATION}) does not appear to be valid for this account."
	fi
}

get-location-vm-attributes() {
	log-message "Getting list of valid VM sizes from cloud provider..."
	while read -r DATA
	do
		VM_NAME=$( echo ${DATA} | awk '{ print $1 }' )
		VM_NAME=$(printf %q "${VM_NAME}")
		VM_MAX_DISK_COUNT[${VM_NAME}]=$( echo ${DATA} | awk '{ print $2 }' )
		VM_RAM[${VM_NAME}]=$( echo ${DATA} | awk '{ print $3 }' )
		VM_CORES[${VM_NAME}]=$( echo ${DATA} | awk '{ print $4 }' )
		VM_OS_DISK_SIZE[${VM_NAME}]=$( echo ${DATA} | awk '{ print $5 }' )
		VM_EPHEMERAL_DISK_SIZE[${VM_NAME}]=$( echo ${DATA} | awk '{ print $6 }' )
	done< <( az vm list-sizes --location ${V4_CFG_CLOUD_PROVIDER_LOCATION} --query '[].{Name:name, MaxDisks:maxDataDiskCount, RAM:memoryInMb, Cores:numberOfCores, OSDiskSize:osDiskSizeInMb, EphemeralDiskSize:resourceDiskSizeInMb}' -o tsv )
}

get-location-resource-utilization-data() {
	log-message "Getting account level resource utilization and quota data from cloud provider..."
	while read -r DATA
	do
		RESOURCE_NAME=$( echo ${DATA} | awk '{ print $1 }' )
		RESOURCE_USAGE_CURRENT[${RESOURCE_NAME}]=$( echo ${DATA} | awk '{ print $2 }' )
		RESOURCE_USAGE_LIMIT[${RESOURCE_NAME}]=$( echo ${DATA} | awk '{ print $3 }' )
	done< <( az vm list-sizes --location ${V4_CFG_CLOUD_PROVIDER_LOCATION} --query --query '[].{Name:name.value, Current:currentValue, Limit:limit}' -o tsv )
}

validate-vm-skus() {
	get-location-vm-attributes
	while read -r line
	do
		VARNAME=${line%=*}
		SKU=${line#*=}
		if [[ "${SKU}" != "NO" ]] ; then
			if [[ "${VM_CORES[${SKU}]:-NA}" = "NA" ]] ; then
				export V4_CFG_REQUESTED_CONFIG_IS_VALID="false"
				log-message "ERROR: ${VARNAME} value of ${SKU} is not valid."
			else
				log-message "${VARNAME} value of ${SKU} is valid."
			fi
		fi
	done< <( printenv | grep ^V4_CFG_VM_SKU_ )

}

validate-resource-availability() {
	get-location-resource-utilization-data
	declare -A CORES_REQUEST_RESOURCE_SUM
	# RESOURCE_USAGE_CURRENT
	# RESOURCE_USAGE_LIMIT
	while read -r line
	do
		VARNAME=${line%=*}
		SKU=${line#*=}
		TYPE=${SKU%_*}
		FAMILY=$( echo $SKU | awk -F_ '{ print $2 }' | tr -d '[:digit:]' )
		VERSION=$( echo $SKU | awk -F_ '{ print $3 }' )
		RESOURCE_STRING="${TYPE}${FAMILY}${VERSION}Family"
		if [[ "${SKU}" != "NO" ]] ; then
			if [[ "${RESOURCE_USAGE_LIMIT[${RESOURCE_STRING}]:-NA}" = "NA" ]] ; then
				export V4_CFG_REQUESTED_CONFIG_IS_VALID="false"
				log-message "ERROR: The requested VM SKU: ${SKU} is not valid because ${RESOURCE_STRING} is not valid for your account in this location."
			elif [[ "${RESOURCE_USAGE_LIMIT[${RESOURCE_STRING}]}" = "0" ]] ; then
				export V4_CFG_REQUESTED_CONFIG_IS_VALID="false"
				log-message "ERROR: The requested VM SKU: ${SKU} is not valid because the account quota for ${RESOURCE_STRING} is 0 your account in this location."
			else
				log-message "The requested VM SKU: ${SKU} (Resource type (${RESOURCE_STRING}) is valid for your account in this location."
				# now start doing the math 
				CORES_REQUEST_RESOURCE_SUM[$SKU]=$(( ${CORES_REQUEST_RESOURCE_SUM[$SKU]:-0} + ${VM_CORES[$SKU]} ))
			fi
		fi
	done< <( printenv | grep ^V4_CFG_VM_SKU_ )	
}

validate-request() {
set -x
	validate-location
	validate-vm-skus
	validate-resource-availability
	#Can't find a way to do this just yet is there a --dry-run option that i could use?
	#validate-pg-sku
set +x
}

set-derivative-variables() {

    export VNET_NAME="${V4_CFG_TARGET_RESOURCE_GROUP}-vnet"
    export V4_CFG_K8S_CLUSTER_NAME="${V4_CFG_TARGET_RESOURCE_GROUP}-k8s"
    export AKS_PRI_NODEPOOL_NM="NP-${V4_CFG_TARGET_RESOURCE_GROUP}-k8s-pool-1"
    export NSG_NAME="${V4_CFG_TARGET_RESOURCE_GROUP}-nsg"
    export V4_CFG_NFS_SVR_NAME="${V4_CFG_TARGET_RESOURCE_GROUP}-${V4_CFG_K8S_TARGET_NAMESPACE}-jump"
    export V4_CFG_POSTGRES_SERVER_NAME="${V4_CFG_TARGET_RESOURCE_GROUP}-pgsql"
    export DEPLOYMENT_NAME="${V4_CFG_DEPLOY_PREFIX}-${V4_CFG_TARGET_RESOURCE_GROUP}-${V4_CFG_CLOUD_PROVIDER_LOCATION}"
	export V4_CFG_DNS_HOST="${V4_CFG_DNS_HOST:-${V4_CFG_TARGET_RESOURCE_GROUP}}"
	export V4_CFG_CAS_SERVER_TYPE="${V4_CFG_CAS_SERVER_TYPE:-smp}"

	if [[ "V4_CFG_CAS_SERVER_TYPE" = "smp" ]] ; then
		export V4_CFG_CAS_WORKER_QTY=${V4_CFG_CAS_WORKER_QTY:-"0"}
		export V4_CFG_CAS_NODE_COUNT=${V4_CFG_CAS_NODE_COUNT:-"1"}
	else
		export V4_CFG_CAS_WORKER_QTY="${V4_CFG_CAS_WORKER_QTY:-"2"}"
		export V4_CFG_CAS_NODE_COUNT=$((${V4_CFG_CAS_WORKER_QTY} + 1))
	fi

}

do-build() {
	#validate-request
	if [[ "${V4_CFG_REQUESTED_CONFIG_IS_VALID}" = "false" ]] ; then
		log-message "can not continue due to validation errors enumerated above.  Please remediate and try again."
		exit 1
	fi

	case "${V4_CFG_DEPLOYMENT_BLUEPRINT}" in 
		basic)
			perform-basic-build
		;;
		standard)
			perform-standard-build
		;;
		premium)
			perform-premium-build
		;;
		*)
			log-message "The requested deployment type (${V4_CFG_DEPLOYMENT_BLUEPRINT}) is not supported."
			usage
			exit 1
		;;
	esac

	export V4_CFG_BUILD_STATUS="complete"
}

do-deployment() {

	if [[ "${V4_CFG_BUILD_STATUS}" != "complete" ]] ; then
        do-build
	fi

    if [ -f ~/.sasAPIkey ]; then 
        MY_SAS_RE_API_KEY=$( sed -e 's/#.*$//' -e '/^$/d' ~/.sasAPIkey )
    else
        echo "ERROR: Could not find ~/.sasAPIkey.  This file must contain a valid secret to enable manifest download."
        exit 1
    fi

    if [ -f ~/.cr.sas.com ]; then 
        SAS_CR_USERID=$( sed -e 's/#.*$//' -e '/^$/d' ~/.cr.sas.com | head -n 1 )
        SAS_CR_PASSWORD=$( sed -e 's/#.*$//' -e '/^$/d' ~/.cr.sas.com | tail -n 1 )
    else
        echo "ERROR: Could not find ~/.cr.sas.com.  This file must contain a valid credentials to enable external registry access."
        echo "       See https://rndconfluence.sas.com/confluence/display/RLSENG/Accessing+internal+container+images+from+external+locations"
        exit 1
    fi

	case "${V4_CFG_DEPLOYMENT_BLUEPRINT}" in 
		basic)
			perform-basic-deployment
		;;
		standard)
			perform-standard-deployment
		;;
		premium)
			perform-premium-deployment
		;;
		*)
			log-message "The requested deployment type (${V4_CFG_DEPLOYMENT_BLUEPRINT}) is not supported."
			usage
			exit 1
		;;
	esac

}

validate-scale-nodes() {
	# All parameters to scale-nodes are positional
	# scale-nodes [nodepool | all] [node-count]

	NODE_POOL="${PARAM_ARRAY[2]:-undefined}"
	NODE_COUNT="${PARAM_ARRAY[3]:-undefined}"
	if [[ "${NODE_POOL}" = "undefined" || "${NODE_COUNT}" = "undefined" ]] ; then
		echo "The deployment scale-nodes command requires two arguments."
		echo "Usage:"
		echo "scale-nodepool [nodepool | all] [node-count]"
		return 1
	fi
	if [[ !( $NODE_COUNT =~ ^-?[0-9]+$ ) ]] ; then
		echo "The node count (specified as ${NODE_COUNT}) must be numeric."
		return 1
	fi
	if [[ ${NODE_POOL} != "all" ]] ; then
		# Check that a node pool of the specified name exists
		EXISTS=$(az aks nodepool list --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --query [].name -o tsv | grep ${NODE_POOL}) 
		if [[ "${EXISTS}" = "${NODE_POOL}" ]] ; then
			return 0
		else
			return 1
		fi
	else
		#all is well
		return 0
	fi

}

do-scale-nodepool() {
	NP=$1
	COUNT=$2
	CURRENT_NODES=$( az aks nodepool show --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --name ${NP} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query count -o tsv )
	if [[ $CURRENT_NODES -eq $COUNT ]] ; then
		log-message "The number of nodes in the ${NP} node pool equals your requested value of ${COUNT}."
	else
		echo "There are currently ${CURRENT_NODES} in the ${NP} nodepool." | tee -a "${LOG_FILE}"
		if [[ "${CMD_LINE_YES:-false}" = "true" ]] ; then
			echo "command line option -y specified: continuing..." | tee -a "${LOG_FILE}"
			REPLY="Y"
		else
			read -p "Would you like to scale to ${COUNT}? " -n 1 -r
			echo
		fi
		if [[ $REPLY =~ ^[Yy]$ ]] ; then
			az aks nodepool scale --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --name ${NP} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --node-count ${COUNT} >>"${LOG_FILE}"
		else
			log-message "User elected NOT to scale the ${NP} node pool."
		fi
	fi
}

do-scale-nodes() {
	if validate-scale-nodes ; then
		if [[ "${NODE_POOL}" = "all" ]] ; then
			# do the whole get list and iterate thing
			while read NP
			do
				do-scale-nodepool "${NP}" ${NODE_COUNT}
			done< <( az aks nodepool list --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --query [].name -o tsv )
		else
			do-scale-nodepool "${NODE_POOL}" ${NODE_COUNT}
		fi
	fi
}

startup-consul() {

	log-message "Starting sas-consul-server"
	kubectl scale statefulset/sas-consul-server --replicas=1
	log-message "Sleeping 30 seconds to allow consul time to start"
	START_COUNT=$( kubectl describe pod sas-consul-server-0 | grep "Started container sas-consul-server" | wc -l )
	until [[ $START_COUNT -eq 1 ]] ; do
		log-message "Waiting for the sas-consul-server container in pod sas-consul-server-0 to start..."
		sleep 10
		START_COUNT=$( kubectl describe pod sas-consul-server-0 | grep "Started container sas-consul-server" | wc -l  )
	done
	log-message "sas-consul-server container has started. Sleeping 30s to allow consul to be ready."
	sleep 30

	cat << 'EOF' >cleanup
#!/usr/bin/env bash

BSC=/opt/sas/viya/home/bin/sas-bootstrap-config

until $BSC catalog services ; do
	echo "Call to list registered services failed.  Will retry in 30s"
	sleep 30
done

while IFS= read -r SVC
do
	echo "Processing: $SVC"
	while read -r SVC_INSTANCE
	do
		INSTANCE=$(echo $SVC_INSTANCE | awk -F, '{ print $2 }' )
		NODE=$(echo $SVC_INSTANCE | awk -F, '{ print $1 }' )
		echo "Deleting instance: $INSTANCE" 
		$BSC --token-file /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/management.token \
			catalog deregister \
			--service-id ${INSTANCE} \
			${NODE}

	done < <( $BSC catalog service ${SVC} | egrep '"serviceID":|"node":' | awk  'NR%2 {printf("%s", $2); next } { print $2 } ' | tr -d '"' )

	echo "registered instances of $SVC:" 
	$BSC catalog service $SVC

done < <( $BSC catalog services | grep serviceName | awk '{ print $2 }' | tr -sd '", ' '' )
EOF

	chmod +x cleanup
	log-message "Deregistering all services from consul.  This may take several minutes."
	kubectl cp cleanup sas-consul-server-0:/tmp/
	if kubectl exec sas-consul-server-0 -- /tmp/cleanup ; then
		return
	else
		log-message "Attempt to cleanup consul service registrations failed.  Will try again in 30 sec"
		if kubectl exec sas-consul-server-0 -- /tmp/cleanup ; then
			log-message "Service registration cleaned up successful."
		else
			log-message "Service registration cleanup failed.  Services may not come up cleanly."
		fi
	fi
}

wait-for-terminating-pods() {
	TERM_COUNT=$( kubectl get pod | grep Terminating | wc -l )
	until [[ $TERM_COUNT -eq 0 ]] ; do
		log-message "There are ${TERM_COUNT} services terminating..."
		sleep 10
		TERM_COUNT=$( kubectl get pod | grep Terminating | wc -l )
	done
}
scale() {
	while read line
	do

		ITEM=`echo $line | awk '{ print $1 }' `
		if [[ "${ITEM}" = "sas-consul-server" && ${REPLICAS} -eq 2 ]] ; then
			# TODO - yes i need to deal with more than 3 replicas but for now here we go.
			REPS=3
		else
			REPS=${REPLICAS}
		fi

		#if [[ "${ITEM}" = "sas-consul-server" && ${REPLICAS} -eq 0 ]] ; then
			# to ensure a happy restart process...
			# do not scale consul to 0 here - to shutdown all consul instances 
			# shutdown-consul is called from the shutdown script.
		#	continue
		#fi

		log-message "Scaling $1/$ITEM --replicas=${REPS}"
		kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} scale $1/$ITEM --replicas=${REPS}  &

	done< <( kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} get $1 --no-headers )
}

do-nodepool-info() {
	log-message "Viya deployment in ${V4_CFG_CLOUD_PROVIDER} resource group ${V4_CFG_TARGET_RESOURCE_GROUP} K8s namespace ${V4_CFG_K8S_TARGET_NAMESPACE} has the following node pools defined:"
	az aks nodepool list --resource-group kegaha --cluster-name kegaha-k8s --query '[].{Name:name, Nodes:count}' -o table | tee -a "${LOG_FILE}"
}

do-scale-deployment() {
	if [[ -z ${REPLICAS+x} ]] ; then
		echo "--replicas must be specified when invoking deployment scale"
		exit 1
	fi
	if [[ $REPLICAS =~ ^-?[0-9]+$ ]] ; then
		if [[ $REPLICAS -eq 0 ]] ; then 
			do-shutdown-deployment
			return
		fi

		echo "The ${V4_CFG_CLOUD_PROVIDER} hosted Viya deployment in resource group ${V4_CFG_TARGET_RESOURCE_GROUP}, K8s namespace ${V4_CFG_K8S_TARGET_NAMESPACE}, will be scaled to ${REPLICAS} replicas." | tee -a "${LOG_FILE}"
		if [[ "${CMD_LINE_YES:-false}" = "true" ]] ; then
			echo "command line option -y specified: continuing..." | tee -a "${LOG_FILE}"
			REPLY="Y"
		else
			read -p "Are you sure? " -n 1 -r
			echo
		fi
		if [[ $REPLY =~ ^[Yy]$ ]] ; then

			if [[ "${SCALE_NODES:-false}" = "true" ]] ; then
				CURRENT_NODES=$( az aks nodepool show --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --name stateless --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query count -o tsv )
				echo "There are currently ${CURRENT_NODES} in the stateless nodepool.  Would you like to scale nodes to the same number as requested replicas (${REPLICAS})?" | tee -a "${LOG_FILE}"
				if [[ "${CMD_LINE_YES:-false}" = "true" ]] ; then
					echo "command line option -y specified: continuing..." | tee -a "${LOG_FILE}"
					REPLY="Y"
				else
					read -p "Do you wish to change the number of nodes? " -n 1 -r
					echo
				fi
				if [[ $REPLY =~ ^[Yy]$ ]] ; then
					az aks nodepool scale --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --name stateless --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --node-count ${REPLICAS} >>"${LOG_FILE}"
				fi
			fi

			CONSUL_RUNNING=$( kubectl get pod | grep sas-consul-server | grep Running | wc -l )
			if [[ $PODS_RUNNING -eq o  ]] ; then
				startup-consul
				# we must be scaling up so start basic services and give them some time to come up before starting all else
				kubectl scale statefulset --replicas=${REPLICAS} --selector=workload.sas.com/class=stateful | tee -a "${LOG_FILE}"
				kubectl scale deployment --replicas=${REPLICAS} --selector=workload.sas.com/class=stateful | tee -a "${LOG_FILE}"
				sleep 20
				kubectl scale deployment --replicas=${REPLICAS} sas-logon-app sas-credentials sas-configuration sas-cachelocator sas-authorization | tee -a "${LOG_FILE}"
				sleep 3m
			fi

			scale deployment
			scale statefulset
			log-message "Viya deployment in ${V4_CFG_CLOUD_PROVIDER} resource group ${V4_CFG_TARGET_RESOURCE_GROUP} K8s namespace ${V4_CFG_K8S_TARGET_NAMESPACE} is scaling to ${REPLICAS} replicas."
			export V4_CFG_INTENDED_REPLICAS="${REPLICAS}"
		else
			log-message "Scale request was not confirmed.  Exiting."
		fi
		# need some logic here to handle scaling up and down... for now commenting this out and watching will be a manual exercise.
#		log-message "Waiting for all services to reach 'Running' state."
#		sleep 30
#		START_COUNT=$( kubectl get pod | grep -v Running | grep -v Completed | wc -l )
#		until [[ $START_COUNT -eq 0 ]] ; do
#			log-message "There are ${START_COUNT} services starting..."
#			sleep 10
#			START_COUNT=$( kubectl get pod | grep -v Running | grep -v Completed | wc -l )
#		done		
	else
		echo "ERROR: The value specified for --replicas must be numeric"
		exit 1
	fi
}

terminate-cas-instances() {
	while read line
	do
		CAS_SERVER=`echo $line | awk '{ print $1 }' `
		while read l
		do
			POD=$(echo $l | awk '{ print $1 }' )
			kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} delete pod/$POD &
		done< <( kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} get pod --no-headers | grep "sas-cas-.*-${CAS_SERVER}-.*" )
	done< <( kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} get casdeployment --no-headers )
}

do-shutdown-deployment() {
	echo "The ${V4_CFG_CLOUD_PROVIDER} hosted Viya deployment in resource group ${V4_CFG_TARGET_RESOURCE_GROUP}, K8s namespace ${V4_CFG_K8S_TARGET_NAMESPACE}, will be shutdown." | tee -a "${LOG_FILE}"
	echo "This action will also delete all CAS servers." | tee -a "${LOG_FILE}"
	if [[ "${CMD_LINE_YES:-false}" = "true" ]] ; then
		echo "command line option -y specified: continuing..." | tee -a "${LOG_FILE}"
		REPLY="Y"
	else
		read -p "Are you sure? " -n 1 -r
		echo
	fi
	if [[ $REPLY =~ ^[Yy]$ ]] ; then
		. "${CONFIG_DIR}/setenv"
		export REPLICAS=0
		log-message "scaling down all stateless services to zero replicas"
		scale deployment
		sleep 5
		wait-for-terminating-pods
		scale statefulset
		wait-for-terminating-pods
		terminate-cas-instances
		wait-for-terminating-pods
		export V4_CFG_INTENDED_REPLICAS="${REPLICAS}"
		echo
		log-message "Shutdown complete."
	else
		log-message "Scale request was not confirmed.  Exiting."
	fi
}

process-deployment-command() {

	SUBCOMMAND="${PARAM_ARRAY[1]}"
	case "${SUBCOMMAND}" in
		scale)
			do-scale-deployment
		;;
		scale-nodes|scale-np|scale-nodepool)
			do-scale-nodes
		;;
		nodepool-info)
		;;
		get-logs)
			collect-deployment-logs
		;;
		shutdown)
			do-shutdown-deployment
		;;
		*)
			echo "The requested deployment subcommand (${SUBCOMMAND}) is not supported."
			exit 1
		;;
	esac
}

validate-environment
