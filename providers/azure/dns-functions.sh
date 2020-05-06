configure-dns-zone() {

    # Support sas names registrations.  We do not register zones with names so if the dns zone ends with .sas.com then just return
    if [[ "${V4_CFG_DNS_ZONE}" == *.sas.com ]] ; then
        return
    fi

    if [[ ${V4_CFG_DNS_ZONE} && ${V4_CFG_DNS_HOST} ]] ; then
        if [[ -z ${V4_CFG_DNS_RESOURCE_GROUP+x} ]] ; then
            log-message "V4_CFG_DNS_RESOURCE_GROUP not defined - setting to V4_CFG_TARGET_RESOURCE_GROUP ( ${V4_CFG_TARGET_RESOURCE_GROUP} )"
            V4_CFG_DNS_RESOURCE_GROUP="${V4_CFG_TARGET_RESOURCE_GROUP}"
        fi
        if ZONE_STATUS=$(az network dns zone show --name ${V4_CFG_DNS_ZONE}  --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} --query name -o tsv); then
            log-message "${ZONE_STATUS} DNS Zone exists"
        else
            log-message "${ZONE_STATUS} DNS Zone does not exist - creating..."
            az network dns zone create --if-none-match \
                --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                --name ${V4_CFG_DNS_ZONE} \
                >>"${LOG_FILE}"
        fi
    else
        log-message "DNS Zone will not be created.  Insufficient parameters specified."
        export V4_CFG_MANAGE_DNS=false;
    fi
}

find-netrc-file() {
    # If we may need a .netrc file let's see if we can find one to use
    if [[ "${V4_CFG_DNS_ZONE}" == *.sas.com && "${V4_CFG_MANAGE_DNS}" = "true" ]] ; then
        V4_CFG_NETRC_FILE=${V4_CFG_NETRC_FILE:-"${CONFIG_DIR}/.netrc"} 
        if [ ! -f "${V4_CFG_NETRC_FILE}" ] ; then
            if [ -f ${HOME}/.netrc ] ; then
                V4_CFG_NETRC_FILE="${HOME}/.netrc"
            else
                log-message "ERROR: Can not find a .netrc file.  Will be unable to manipulate DNS information in names.sas.com."
                # At some point add logic to print messages nicely rather than fail... at least for 
                # time being we will fail and things will be ugly but the info needed to manually configure
                # DNS will be emitted so leaving this as a TODO item for now.
            fi
        fi
        log-message "INFO: Using ${V4_CFG_NETRC_FILE} for DNS manipulation authorization"
    fi
}

# TODO: - turns out that need to check the HTTP status on the CURL command for names.sas.com updates.
# need to write that

create-or-replace-dns-A-record() {
    # $1 passed should be the hostname
    # $2 passed should be the IP Address

    find-netrc-file
    if [[ "${V4_CFG_MANAGE_DNS}" = "true" ]] ;  then
        if [[ "${V4_CFG_DNS_ZONE}" != *.sas.com ]] ; then
            if [[ ${V4_CFG_DNS_ZONE} && ${1} && ${2} ]] ; then
                if [[ -z ${V4_CFG_DNS_RESOURCE_GROUP} ]] ; then
                    log-message "V4_CFG_DNS_RESOURCE_GROUP not defined - setting to V4_CFG_TARGET_RESOURCE_GROUP ( ${V4_CFG_TARGET_RESOURCE_GROUP} )"
                    V4_CFG_DNS_RESOURCE_GROUP="${V4_CFG_TARGET_RESOURCE_GROUP}"
                fi
                if ZONE_STATUS=$(az network dns zone show --name ${V4_CFG_DNS_ZONE}  --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} --query name -o tsv) ; then
                    log-message "${ZONE_STATUS} DNS Zone exists"
                else
                    log-message "${ZONE_STATUS} DNS Zone does not exist - creating..."
                    az network dns zone create --if-none-match \
                    --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                    --name ${V4_CFG_DNS_ZONE} \
                    >>"${LOG_FILE}"
                fi
            else
                log-message "DNS Zone will not be created.  Insufficient parameters specified."
                export V4_CFG_MANAGE_DNS=false;
            fi
        fi
    fi

    if [[ "${V4_CFG_MANAGE_DNS}" = "true" ]] ;  then
        if [[ "${V4_CFG_DNS_ZONE}" == *.sas.com ]] ; then
            if DNS_CONFIG=$( host ${1}.${V4_CFG_DNS_ZONE} ) ; then
                # our hostname exists so need to change the address
                DNS_CONFIG=$( echo ${DNS_CONFIG} | awk '{ print $4 }' )
                echo "Found existing DNS CONFIG for ${1}.${V4_CFG_DNS_ZONE}: ${DNS_CONFIG} " >>"${LOG_FILE}"
                if [[ "${DNS_CONFIG}" != "${2}" ]] ; then
                    if STATUS=$( curl --netrc-file ${V4_CFG_NETRC_FILE} "http://names.sas.com/Api.php?op=C&nm0=${1}.${V4_CFG_DNS_ZONE}&rd0=${DNS_CONFIG}&cd0=${2}" ) ; then
                        log-message "Request to add IP address ${2} for ${1}.${V4_CFG_DNS_ZONE} queued to names.sas.com successfully."
                        log-message "${STATUS}"
                    else
                        log-message "Request to add IP address ${2} for ${1}.${V4_CFG_DNS_ZONE} failed to queue to names.sas.com - STATUS:"
                        log-message "${STATUS}"
                    fi
                else
                    log-message "Current DNS Address ${DNS_CONFIG} matches requested address ${2} - no changes needed"
                fi
            else
                # our hostname does not exist so need to add the address
                log-message "Requested hostname not found in DNS.  Adding..."
                if STATUS=$( curl --netrc-file ${V4_CFG_NETRC_FILE} "http://names.sas.com/Api.php?op=A&nm0=${1}.${V4_CFG_DNS_ZONE}&rd0=${2}" ) ; then
                    log-message "Request to add IP address ${2} for ${1}.${V4_CFG_DNS_ZONE} queued to names.sas.com successfully."
                    log-message "${STATUS}"
                else
                    log-message "Request to add IP address ${2} for ${1}.${V4_CFG_DNS_ZONE} failed to queue to names.sas.com - STATUS:"
                    log-message "${STATUS}"
                fi
            fi
        else
            #check to see if A record exists
            if A_REC_STATUS=$(az network dns record-set a show --name ${1} --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} --zone-name ${V4_CFG_DNS_ZONE} --query name -o tsv 2>&1 ) ; then
                log-message "The A recordset for ${1} already exists in zone ${V4_CFG_DNS_ZONE}"
                if IP_ADDRESSES=$(az network dns record-set a show --name ${1} --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} --zone-name ${V4_CFG_DNS_ZONE} --query "arecords" -o tsv) ; then
                    if [[ ${IP_ADDRESSES} = "" ]] ; then
                        log-message "There are no IP Addresses defined for this record.  Setting to ${2} "
                        az network dns record-set a add-record \
                        --ipv4-address ${2} \
                        --record-set-name ${1} \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        >>"${LOG_FILE}"

                    else
                        log-message "The current IP Address is: ${IP_ADDRESSES}.  V4_CFG_MANAGE_DNS is true."
                        log-message "Deleting the current IP address."
                        az network dns record-set a remove-record \
                        --ipv4-address ${IP_ADDRESSES} \
                        --record-set-name ${1} \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        --keep-empty-record-set \
                        >>"${LOG_FILE}"

                        log-message "Adding IP address ${2} for ${1}"
                        az network dns record-set a add-record \
                        --ipv4-address ${2} \
                        --record-set-name ${1} \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        >>"${LOG_FILE}"

                    fi
                fi
            else
                log-message "Adding IP address ${2} for ${1}"
                az network dns record-set a add-record \
                    --ipv4-address ${2} \
                    --record-set-name ${1} \
                    --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                    --zone-name ${V4_CFG_DNS_ZONE} \
                    >>"${LOG_FILE}"
            fi
        fi
    else
        log-message "V4_CFG_MANAGE_DNS set to false.  Will not process A record request."
    fi
}

create-or-replace-dns-wildcard-cname() {
    # $1 is the hostname

    find-netrc-file
    if [[ "${V4_CFG_MANAGE_DNS}" = "true" ]] ;  then
        # Validate the host A record exists
        if [[ "${V4_CFG_DNS_ZONE}" == *.sas.com ]] ; then
            # Ensure we're not going to try to do something very bad to SAS DNS
            if [[ "${V4_CFG_DNS_ZONE}" = "sas.com" || "${V4_CFG_DNS_ZONE:-missing}" = "missing" ]] ; then
                log-message "ERROR: Can NOT register a wildcard DNS without a hostname or if hostname = 'sas.com' value provided: ${V4_CFG_DNS_ZONE}."
                return
            fi
            # We're not going to validate that the A record exists because we may have that request queued... so simply going to see if the CNAME exists
            # Evidently if the IP address of a DNS name is changed the alias records are deleted.  We will always log a request to add the alias to cover
            # our bases...
            #if DNS_CONFIG=$( host \*.${1}.${V4_CFG_DNS_ZONE} ) ; then
            #    log-message "wildcard host definition found:"
            #    log-message "${DNS_CONFIG}"
            #else
                if STATUS=$( curl --netrc-file ${V4_CFG_NETRC_FILE}  "http://names.sas.com/Api.php?op=A&nm0=*.${1}.${V4_CFG_DNS_ZONE}&rd0=${1}.${V4_CFG_DNS_ZONE}" ) ; then
                    log-message "Request to add DNS wildcard *.${1}.${V4_CFG_DNS_ZONE} for ${1}.${V4_CFG_DNS_ZONE} queued to names.sas.com successfully."
                    log-message "${STATUS}"
                else
                    log-message "Request to add DNS wildcard *.${1}.${V4_CFG_DNS_ZONE} for ${1}.${V4_CFG_DNS_ZONE} failed to queue to names.sas.com STATUS:"
                    log-message "${STATUS}"
                fi
            #fi
        else
            if A_REC_STATUS=$(az network dns record-set a show --name ${1} --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} --zone-name ${V4_CFG_DNS_ZONE} --query name -o tsv 2>&1 ) ; then
                log-message "The A recordset for ${1} already exists in zone ${V4_CFG_DNS_ZONE}"
                if IP_ADDRESSES=$(az network dns record-set a show --name ${1} --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} --zone-name ${V4_CFG_DNS_ZONE} --query "arecords" -o tsv) ; then
                    if [[ ${IP_ADDRESSES} = "" ]] ; then
                        log-message "WARNING: The host A record specified \( ${1} \) exists but there is no associated IP address.  CNAME record will be created "
                        az network dns record-set cname create \
                        --name "\*.${1}" \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        >>"${LOG_FILE}"

                        az network dns record-set cname set-record \
                        --cname "${1}.${V4_CFG_DNS_ZONE}" \
                        --record-set-name "*.${1}" \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        >>"${LOG_FILE}"
                    else
                        log-message "The current IP Address is: ${IP_ADDRESSES}.  V4_CFG_MANAGE_DNS is true."
                        log-message "Adding wildcard CNAME record"
                        az network dns record-set cname create \
                        --name "\*.${1}" \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        >>"${LOG_FILE}"

                        az network dns record-set cname set-record \
                        --cname "${1}.${V4_CFG_DNS_ZONE}" \
                        --record-set-name "*.${1}" \
                        --resource-group ${V4_CFG_DNS_RESOURCE_GROUP} \
                        --zone-name ${V4_CFG_DNS_ZONE} \
                        >>"${LOG_FILE}"
                    fi
                fi
            else
                log-message "ERROR: The host A record specified \( ${1} \) does not exist.  CNAME record will not be created."
            fi
        fi
    else
        log-message "V4_CFG_MANAGE_DNS set to false.  Will not process CNAME request."
    fi

}
