collect-deployment-logs() {

	VIYA_LOGS_DIR="${DEPLOYMENT_DIR}/viya-logs"
	cd "${DEPLOYMENT_DIR}"
	if [ ! -d "${VIYA_LOGS_DIR}" ] ; then
		mkdir -p "${VIYA_LOGS_DIR}"
	fi

	mkdir "${VIYA_LOGS_DIR}/${DT_EXT}"
	while read -r POD ; 
	do
		CONTAINER_NAME=${POD%-*}
		CONTAINER_NAME=${CONTAINER_NAME%-*}
		if [[ "${CONTAINER_NAME}" = "sas-cas-server"* ]] ; then
			CONTAINER_NAME=cas
		fi
		kubectl logs ${POD} -c ${CONTAINER_NAME} > "${VIYA_LOGS_DIR}/${DT_EXT}/${POD}.log"
	done< <( kubectl get pod -o=custom-columns=NAME:.metadata.name --no-headers )
	
}
