setup-postgres-server() {

	log-message "Creating Azure Database for PostgreSQL deployment"    

	if VNET_STATUS=$(az postgres server show --name ${V4_CFG_POSTGRES_SERVER_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query name -o tsv 2>&1 ); then
            log-message "Postgres server named ${V4_CFG_POSTGRES_SERVER_NAME} exists.  Will use as-is."
    else
		az postgres server create \
			--admin-password ${V4_CFG_POSTGRES_PASSWORD} \
			--admin-user ${V4_CFG_POSTGRES_USER_NAME}  \
			--name ${V4_CFG_POSTGRES_SERVER_NAME}  \
			--sku-name ${V4_CFG_POSTGRES_SKU} \
			--ssl-enforcement Disabled \
			--auto-grow Enabled \
			--storage-size ${V4_CFG_POSTGRES_INIT_STORAGE} \
			--backup-retention ${V4_CFG_POSTGRES_BKUP_RETENTION_DAYS} \
			--version ${V4_CFG_POSTGRES_VERSION} \
			>>"${LOG_FILE}"

		echo "Creating postgres vnet rule"
		az postgres server vnet-rule create \
			--name ${VNET_NAME}-pgsql \
			--server-name ${V4_CFG_POSTGRES_SERVER_NAME} \
			--subnet ${VNET_NAME}-misc-subnet \
			--vnet-name ${VNET_NAME} \
			>>"${LOG_FILE}"

		echo "Creating postgres vnet rule"
		az postgres server vnet-rule create \
			--name ${VNET_NAME}-pgsql \
			--server-name ${V4_CFG_POSTGRES_SERVER_NAME} \
			--subnet ${VNET_NAME}-aks-subnet \
			--vnet-name ${VNET_NAME} \
			>>"${LOG_FILE}"
	fi	
	# Now collect information needed to drive deployment of Viya into the environment
	# will need to get this info and pass along regardless of provision status to support 
	# viya deployment changes without updates to compute configuration.
	V4_CFG_POSTGRES_FQDN=$(az postgres server show --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --name ${V4_CFG_POSTGRES_SERVER_NAME} --query fullyQualifiedDomainName -o tsv)
	V4_CFG_POSTGRES_ADMIN_LOGIN="${V4_CFG_POSTGRES_USER_NAME}@${V4_CFG_POSTGRES_SERVER_NAME}"

    declare -A GLOBAL_VARS
    eval "GLOBAL_VARS[V4_CFG_POSTGRES_FQDN]="${V4_CFG_POSTGRES_FQDN}" "
    eval "GLOBAL_VARS[V4_CFG_POSTGRES_ADMIN_LOGIN]="${V4_CFG_POSTGRES_ADMIN_LOGIN}" "
    declare -p GLOBAL_VARS >"${DEPLOYMENT_DIR}/.tmp.$$.${FUNCNAME}"

	log-message "Azure Database for PostgreSQL deployment complete"
}
