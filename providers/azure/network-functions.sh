create-subnet() {

	log-message "Creating SUBNET: ${1}"
	if SUBNET_STATUS=$(az network vnet subnet show --name ${1} --vnet-name ${VNET_NAME} --query name -o tsv 2>&1) ; then
		log-message "SUBNET ${1} exists.  Will use as-is."
	else
		log-message "Creating AKS subnet..."
		az network vnet subnet create \
			--name "${1}" \
			--vnet-name ${VNET_NAME} \
			--network-security-group "${NSG_NAME}" \
			--address-prefixes ${2} \
			--service-endpoints Microsoft.Storage Microsoft.Sql Microsoft.AzureActiveDirectory Microsoft.KeyVault Microsoft.ContainerRegistry \
			>>"${LOG_FILE}"
	fi
}

create-vnet() {

	if VNET_STATUS=$(az network vnet show --name ${VNET_NAME} --query name -o tsv 2>&1); then
            log-message "VNET ${VNET_NAME} exists.  Will use as-is."
	else
		log-message "Creating VNET 192.168.0.0/16 "
		az network vnet create \
			--name "${VNET_NAME}" \
			--address-prefixes 192.168.0.0/16 >>"${LOG_FILE}"
	fi 

	if NSG_STATUS=$(az network nsg show --name ${NSG_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query name -o tsv 2>&1) ; then
		log-message "NSG ${NSG_NAME} exists.  Will use as-is."
	else
		log-message "Creating Network Security Group"
		az network nsg create -n ${NSG_NAME} >>"${LOG_FILE}"
		log-message "Creating NSG Rules defined in nsg-rules.txt"
	fi
	create-nsg-rules ${NSG_NAME} ${V4_CFG_TARGET_RESOURCE_GROUP}

	create-subnet "${VNET_NAME}-gw-subnet" "192.168.0.0/24"
	create-subnet "${VNET_NAME}-aks-subnet" "192.168.1.0/24"
	create-subnet "${VNET_NAME}-misc-subnet" "192.168.2.0/24"
	export K8S_SUBNET_ID=$(az network vnet subnet show -g ${V4_CFG_TARGET_RESOURCE_GROUP}  --vnet-name ${VNET_NAME} --name "${VNET_NAME}-aks-subnet" --query "id" -o tsv )
	log-message "Network config completed."
}
