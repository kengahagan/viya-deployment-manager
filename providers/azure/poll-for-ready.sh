poll-for-ready() {
	
	echo "Polling for SASLogon pod..."
	until [[ "${SASLOGON_POD}" != "" ]] ; do
		SASLOGON_POD=$( kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} get pod | grep sas-logon | awk '{ print $1 }' )
	done
	echo "Found SASLogon pod - name: ${SASLOGON_POD}"

	until [[ "${SASBOOT_RESET}" != "" ]] ; do
		echo "Sleeping for 60 seconds then Polling for sasboot password reset url..." 
		sleep 60
		SASBOOT_RESET=$( kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE}  logs ${SASLOGON_POD} | grep sasboot | awk -F': ' '{ print $2 }' )
	done


	if [[ "${V4_CFG_MANAGE_DNS}" = "true" ]] ; then
		SASLogon_URL="${URL_PREFIX}${V4_CFG_K8S_TARGET_NAMESPACE}.${V4_CFG_DNS_HOST}.${V4_CFG_DNS_ZONE}"
	else
		SASLogon_URL="${URL_PREFIX}${V4_CFG_K8S_TARGET_NAMESPACE}.${INGRESS_IP_ADDR}"
	fi
	echo "sasboot password reset url is: ${SASLogon_URL}${SASBOOT_RESET}"

	until [[ "${LOGON_PAGE}" != "" ]] ; do
		sleep 30
		LOGON_PAGE=$( curl  ${SASLogon_URL}/SASLogon/login )
	done
	echo Status:  $(date "+%Y.%m.%d.%H.%M.%S") SASLogon page is responding!

}
