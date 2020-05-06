setup-nfs-server() {
	# Create NFS Server
	#TODO: create deployment specific keys and load into ssh-agent for subsequent use
	log-message "Creating NFS/jumpbox server..."
	if V4_CFG_NFS_SVR_CONFIG=$(az vm show --name ${V4_CFG_NFS_SVR_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} 2>&1 ); then
        log-message "VM named ${V4_CFG_NFS_SVR_NAME} exists.  Will use as-is."
		export V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS=$(az vm show -d --name ${V4_CFG_NFS_SVR_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query "privateIps" -o tsv)
		export V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS=$(az vm show -d --name ${V4_CFG_NFS_SVR_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query "publicIps" -o tsv)
    else
		if [ ! -d "${CONFIG_DIR}/.ssh" ] ; then
			mkdir "${CONFIG_DIR}/.ssh"
			chmod 700 "${CONFIG_DIR}/.ssh"
		fi
		if [ ! -f "${CONFIG_DIR}/.ssh/${V4_CFG_NFS_SVR_NAME}" ] ; then
			ssh-keygen -b 2048 -t rsa -f "${CONFIG_DIR}/.ssh/${V4_CFG_NFS_SVR_NAME}" -q -N ""
			export V4_CFG_JUMPBOX_SSH_KEY="${CONFIG_DIR}/.ssh/${V4_CFG_NFS_SVR_NAME}"
		fi
		V4_CFG_NFS_SVR_CONFIG=$( az vm create \
			--name ${V4_CFG_NFS_SVR_NAME} \
			--accelerated-networking true \
			--admin-username ${V4_CFG_DEPLOYMENT_ADMIN_ID} \
			--data-disk-caching ReadOnly \
			--nsg ${NSG_NAME} \
			--size ${V4_CFG_VM_SKU_JUMPBOX} \
			--image Canonical:UbuntuServer:18.04-LTS:latest \
			--priority Regular \
			--authentication-type ssh \
			--ssh-dest-key-path /home/${V4_CFG_DEPLOYMENT_ADMIN_ID}/.ssh/authorized_keys \
			--ssh-key-values @"${CONFIG_DIR}/.ssh/${V4_CFG_NFS_SVR_NAME}.pub" \
			--subnet "${VNET_NAME}-misc-subnet" \
			--vnet-name "${VNET_NAME}" \
			--os-disk-size-gb 64 \
			--data-disk-sizes-gb 128 128 128 128 \
			--data-disk-caching ReadOnly \
			--public-ip-sku Basic \
			--public-ip-address-allocation static \
			--custom-data @"${CONFIG_DIR}/cloud-init.txt" )

			echo ${V4_CFG_NFS_SVR_CONFIG} >>"${LOG_FILE}"

		export V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS=$(az vm show -d --name ${V4_CFG_NFS_SVR_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query "privateIps" -o tsv)
		export V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS=$(az vm show -d --name ${V4_CFG_NFS_SVR_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query "publicIps" -o tsv)
	fi

	echo "${V4_CFG_NFS_SVR_CONFIG}" >>"${LOG_FILE}"

	log-message "NFS/jumpbox server public IP address: ${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS} "
	create-or-replace-dns-A-record "${V4_CFG_NFS_SVR_NAME}" "${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS}"
	log-message "NFS/jumpbox server private IP address: ${V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS} "
	#create-or-replace-dns-A-record "${V4_CFG_NFS_SVR_NAME}-int" "${V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS}"

    declare -A GLOBAL_VARS
    eval "GLOBAL_VARS[V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS]="${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS}" "
    eval "GLOBAL_VARS[V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS]="${V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS}" "
    declare -p GLOBAL_VARS >"${DEPLOYMENT_DIR}/.tmp.$$.${FUNCNAME}"

}
