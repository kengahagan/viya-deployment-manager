create-nsg-rules() {
    # $1 is the NSG Name
    # $2 is the resource group name
    if [[ "${V4_CFG_BUILD_STATUS:-incomplete}" = "incomplete" || ( "${V4_CFG_BUILD_STATUS}" = "complete" && "${REFRESH_NETWORK_SECURITY:-false}" = "true") ]] ; then
        MYDIR=$(mktemp -d "${TMPDIR:-/tmp/}$(basename $0).XXXXXXXXXXXX")
        RULEFILE=$(mktemp "${MYDIR}/nsg-rules.XXXXXXXXXXXX")

        sed -e 's/#.*$//' -e '/^$/d' "${CONFIG_DIR}/nsg-rules.txt" >${RULEFILE}

        DELIM='|'
        while IFS= read -r line
        do
        vals=()
        while [[ $line ]]; 
        do
            vals+=( "${line%%"$DELIM"*}" );
            line=${line#*"$DELIM"};
        done;
        PRIORITY="${vals[0]}"
        DIRECTION="${vals[1]}"
        TYPE="${vals[2]}"
        PROTO="${vals[3]}"
        SOURCE_RANGE="${vals[4]}"
        SOURCE_PORT="${vals[5]}"
        DEST_RANGE="${vals[6]}"
        DEST_PORT="${vals[7]}"
        NAME="${vals[8]}"
        DESC="${vals[9]}"
        
        log-message "Creating NSG rule: ${DESC}"
        az network nsg rule create \
            --name "${NAME}"  \
            --nsg-name "${1}" \
            --resource-group "${2}" \
            --access "${TYPE}" \
            --description \""${DESC}"\" \
            --destination-address-prefixes "${DEST_RANGE}" \
            --destination-port-ranges "${DEST_PORT}" \
            --priority "${PRIORITY}" \
            --direction "${DIRECTION}" \
            --protocol "${PROTO}" \
            --source-address-prefixes "${SOURCE_RANGE}" \
            --source-port-ranges "${SOURCE_PORT}"  \
            >>"${LOG_FILE}"

        done < "${RULEFILE}"

        # TODO: should probably grep -v anthing that is comprised of entirely alpha chars.
        export V4_CFG_K8S_AUTHORIZED_NETWORKS=$( awk -F '|' '{ print $5 }' "${RULEFILE}" | grep -v GatewayManager | sort -u | awk -v ORS=, '{ print $1 }' | sed 's/,$//' )
        rm -rf ${MYDIR}
    else
        log-message "Build status complete - network security rules will not be refreshed.  To force refresh add --update-network-security-rules"
    fi
}
