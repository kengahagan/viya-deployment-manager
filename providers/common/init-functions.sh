# this will need some more cleanup but okay for now
validate-provider() {

    if [ -d "${SCRIPT_DIR}/providers/${V4_CFG_CLOUD_PROVIDER}" ] ; then
        if [ -f "${SCRIPT_DIR}/providers/${V4_CFG_CLOUD_PROVIDER}/validation-functions.sh" ] ; then
            . "${SCRIPT_DIR}/providers/${V4_CFG_CLOUD_PROVIDER}/validation-functions.sh"
        else
            echo "ERROR: The specified provider is valid but no validation functions have yet been created."
            exit 1
        fi
    else
        echo "ERROR: The specified provider: ${V4_CFG_CLOUD_PROVIDER} is not valid."
        usage
        exit 1
    fi
}

support-adr-37() {
    # This function allows previous deployment directories to be transformed into the new ADR-37 structure.
    # https://gitlab.sas.com/convoy/lib/sonder/-/blob/master/doc/arch/adr-37-bundles-examples-overlays.md
    # https://rndconfluence.sas.com/confluence/display/RNDDEVOPS/Ordering+Announcement
    if [ -d "${DEPLOYMENT_DIR}/config" ] ; then
        mv "${DEPLOYMENT_DIR}/config" "${DEPLOYMENT_DIR}/site-config"
        ln -s "${DEPLOYMENT_DIR}/site-config" "${DEPLOYMENT_DIR}/config"
    fi
}

global-init() {

    #export SCRIPT_DIR="$( cd "$( dirname $(dirname $(dirname "${BASH_SOURCE[0]}" )))" >/dev/null 2>&1 && pwd )"
    export DT_EXT=$(date "+%Y.%m.%d.%H.%M.%S")
    export DEPLOYMENTS_DIR="${SCRIPT_DIR}/deployments"
    if [[ -L "${DEPLOYMENTS_DIR}/default" && -d "${DEPLOYMENTS_DIR}/default" ]] ; then
        # A default deployment has been set
        export DEFAULT_DEPLOYMENT="${DEPLOYMENTS_DIR}/default"
    fi

    # Handle some host deltas
    if [ "$(uname)" == "Darwin" ]; then
        SED_IN_PLACE='-i""'
    else
        SED_IN_PLACE='-i'
    fi

    # OKAY this is quick and doing minimal checking - should probably help more...
    #TODO: Make this better
    BASH_VERSION=$(/usr/bin/env bash -c 'echo "${BASH_VERSINFO:-0}"')
    if [[ "${BASH_VERSION}" -lt 4 ]] ; then
        echo "ERROR: BASH version must be 4 or higher to run this tool."
        exit 1
    fi

}

setup-log-file() {

    export LOG_DIR="${DEPLOYMENT_DIR}/logs"
    if [ ! -d "${LOG_DIR}" ] ; then
        mkdir "${LOG_DIR}"
    fi
    export LOG_FILE="${LOG_DIR}/${DT_EXT}-${COMMAND}.log"
    # Redirect all standard out to log file
    exec > >(tee -i "${LOG_FILE}")
    # Catch error output too
    exec 2>&1
    log-message "Command Initiated."
    log-message "Logging to ${LOG_FILE}"
    log-message "execute tail -f ${LOG_FILE} in another window for more detailed status"

}

log-message() {
    echo "Status:  $(date "+%Y.%m.%d.%H.%M.%S") $1" | tee -a "${LOG_FILE}" 
}

set-variables-from-subtask() {

    . "${DEPLOYMENT_DIR}/.tmp.$$.$1"
    for i in "${!GLOBAL_VARS[@]}"
    do
        eval export "${i}"="${GLOBAL_VARS[$i]}"
    done
    rm -f "${DEPLOYMENT_DIR}/.tmp.$$.$1"

}

display-global-options() {

    echo "The following options can be passed to any command:"
    echo
    echo -e "\t-c,\t--config | --configuration [basic|standard|premium]"
    echo -e "\t-g,\t--resource-group <resourceGroup>"
    echo -e "\t-i,\t--infrastructure-only  (run kustomize but do not install viya)"
    echo -e "\t-l,\t--ldap\tDeploy and convigure viya to embedded ldap server"
    echo -e "\t-n,\t--k8s-namespace <namespace>"
    echo -e "\t-p,\t--provider [azure|aws|gcp|custom]"
    echo -e "\t-t,\t--tls\tEnables TLS configuration"
    echo -e "\t-h,\t--help"
    echo ""

}

usage() {

    echo "viya-deployment manages a viya deployment and optionally manages associated cloud infrastructure"
    echo "    NOTE: most configuration is not currently supported via command line"
    echo "          arguments.  If you do not see an argument enumerated here chances"
    echo "          are good that the parameter can be changed by editing the variables"
    echo "          set at the top of the script"
    echo 
    echo "Usage:"
    echo "viya-deployment [flags] [options]"
    echo
    echo "Use \"viya-deployment <command> --help\" for more information about a given command."
    echo "Use \"viya-deployment options\" for a list of global command-line options (applies to all commands)."
    echo
}

read-config-defaults() {
    # Reads config defaults from the specified location - if it exists in the passed directory
    DEFAULT_FILE="$1"
    if [ -f "${DEFAULT_FILE}" ] ; then
        DEFAULT_TMP=$(mktemp "${SCRIPT_DIR}/.tmp.defaults.XXXXXXXXXXXX")
        sed -e 's/#.*$//' -e '/^$/d' "${DEFAULT_FILE}" >"${DEFAULT_TMP}"
        while IFS= read -r LINE
        do
            KEY="${LINE%=*}"
            VALUE="${LINE#*=}"
            DEFAULT_ARGS[${KEY}]="${VALUE}"
            ARG_SOURCE[${KEY}]="${DEFAULT_FILE}"
        done < "${DEFAULT_TMP}"
        rm -f "${DEFAULT_TMP}"
    fi
}

process-defaults() {
    DEFAULT_FILE="${1}/site-config/defaults"
    if [ -f "${DEFAULT_FILE}" ] ; then 
        read-config-defaults "${DEFAULT_FILE}"
    fi

}

get-value-for() {
    if [[ -z "${USER_ARGS[$1]+x}" ]] ; then
        if [[ -z "${DEFAULT_ARGS[$1]+x}" ]] ; then
            return 1
        else
            eval export $1=""""${DEFAULT_ARGS[$1]}""""
            return 0
        fi
    else
        eval export $1=""""${USER_ARGS[$1]}""""
        return 0        
    fi
}

export-undefined-vars-from-array() {

    var=$(declare -p "$1")
    eval declare -A _arr=${var#*=}
    for KEY in "${!_arr[@]}"; do
        if [[ "${!KEY}" = "" ]] ; then
            eval export $KEY=""""${_arr[$KEY]}""""
        fi
    done

}

debug-print() {
   
    echo "Default values:"
    for K in "${!DEFAULT_ARGS[@]}"; do echo $K --- ${DEFAULT_ARGS[$K]}; done
    echo
    echo "Command line values:"
    for K in "${!USER_ARGS[@]}"; do echo $K --- ${USER_ARGS[$K]}; done
    export -p

}

set-vars-from-config() {
    # process command line variables and then if needed - the default deployment link to set variables
    # in proper precesidence (provider / account / resource group / namespace)

    if [[ "${USER_ARGS[CONFIG_FILE]:-undefined}" != "undefined" ]] ; then
        if [ -f "${USER_ARGS[CONFIG_FILE]}" ] ; then
            read-config-defaults "${USER_ARGS[CONFIG_FILE]}"
        else
            echo "The specified config file does not exist"
            exit 1
        fi
    else
        process-defaults "${SCRIPT_DIR}"

        get-value-for "V4_CFG_CLOUD_PROVIDER" && process-defaults "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}" 
        get-value-for "V4_CFG_CLOUD_PROVIDER_ACCOUNT" && process-defaults "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}" 
        get-value-for "V4_CFG_TARGET_RESOURCE_GROUP" && process-defaults "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/${V4_CFG_TARGET_RESOURCE_GROUP}"
        get-value-for "V4_CFG_K8S_TARGET_NAMESPACE" && process-defaults "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/${V4_CFG_TARGET_RESOURCE_GROUP}/${V4_CFG_K8S_TARGET_NAMESPACE}"

    fi

    export-undefined-vars-from-array "USER_ARGS"
    export-undefined-vars-from-array "DEFAULT_ARGS"

    #debug-print
    #exit

}

create-env-script() {
    ENV_SCRIPT="${CONFIG_DIR}/setenv"
    echo export KUBECONFIG=""""${V4_CFG_K8S_KUBECONFIG}"""" >"${ENV_SCRIPT}"
    echo kubectl config set-context --current --namespace="${V4_CFG_K8S_TARGET_NAMESPACE}" >>"${ENV_SCRIPT}"
}

update-deployment-config() {
    # update the config file for this deployment with values from this run
    if [ -f "${CONFIG_DIR}/defaults" ] ; then
        mv "${CONFIG_DIR}/defaults" "${CONFIG_DIR}/defaults.${DT_EXT}"
    fi

    echo "# Config values updated by viya-deployment script on ${DT_EXT} " >"${CONFIG_DIR}/defaults"
    set | grep ^V4_CFG_ >>"${CONFIG_DIR}/defaults"

    create-env-script
}

do-command-prep() {
    # The build command needs provider / account / target resource group / target namespace before it can run.
    # ensure these are defined and validate each one before continuing 
    if [[ -z "${V4_CFG_CLOUD_PROVIDER+x}" ]] ; then
        echo "ERROR: The build command requires that a provider be defined"
        exit 1
    else 
        validate-provider
    fi
    if [[ -z "${V4_CFG_CLOUD_PROVIDER_ACCOUNT+x}" ]] ; then
        echo "ERROR: The build command requires that an account be defined"
        exit 1
    else
        validate-account
    fi
    if [[ -z "${V4_CFG_TARGET_RESOURCE_GROUP+x}" ]] ; then
        echo "ERROR: The build command requires that a resource group be defined"
        exit 1
    fi
    if [[ -z "${V4_CFG_K8S_TARGET_NAMESPACE+x}" ]] ; then
        echo "ERROR: The build command requires that a namespace be defined"
        exit 1
    fi

    export DEPLOYMENT_DIR="${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/${V4_CFG_TARGET_RESOURCE_GROUP}/${V4_CFG_K8S_TARGET_NAMESPACE}"
    support-adr-37
    export CONFIG_DIR="${DEPLOYMENT_DIR}/site-config"

    if [ ! -d "${DEPLOYMENT_DIR}" ]; then
        mkdir -p "${DEPLOYMENT_DIR}"
    fi

    if [ ! -d "${CONFIG_DIR}" ]; then
        mkdir -p "${CONFIG_DIR}"
        if [ -d "${SCRIPT_DIR}/config" ] ; then
            cp -r "${SCRIPT_DIR}/config" "${DEPLOYMENT_DIR}/"
        fi
        if [ -d "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/config" ] ; then
            cp -r "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/config" "${DEPLOYMENT_DIR}/"
        fi
        if [ -d "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/config" ] ; then
            cp -r "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/config" "${DEPLOYMENT_DIR}/"
        fi
        if [ -d "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/${V4_CFG_TARGET_RESOURCE_GROUP}/config" ] ; then
            cp -r "${DEPLOYMENTS_DIR}/${V4_CFG_CLOUD_PROVIDER}/${V4_CFG_CLOUD_PROVIDER_ACCOUNT}/${V4_CFG_TARGET_RESOURCE_GROUP}/config" "${DEPLOYMENT_DIR}/"
        fi
        # If we're creating this directory fresh makes no sense to keep the config/defaults file.
        if [ -f "${CONFIG_DIR}/defaults" ] ; then
            rm -f "${CONFIG_DIR}/defaults"
        fi
        
    fi

    if [ ! -d "${CONFIG_DIR}/.kube" ]; then
        mkdir -p "${CONFIG_DIR}/.kube"
    fi

    setup-log-file
    cd "${DEPLOYMENT_DIR}"
    export V4_CFG_K8S_KUBECONFIG="${CONFIG_DIR}/.kube/config"
    export KUBECONFIG="${V4_CFG_K8S_KUBECONFIG}"

	set-derivative-variables

    if [ -d "${DEPLOYMENT_DIR}/bundles/default/internal/components" ] ; then
        export COMPONENTS_DIR="${DEPLOYMENT_DIR}/bundles/default/internal/components"
    else
        export COMPONENTS_DIR="${DEPLOYMENT_DIR}/sas-bases/base/components"
    fi

    for f in ${SCRIPT_DIR}/providers/common/*.sh ; do
        if [[ "$f" != "${SCRIPT_DIR}/providers/common/init-functions.sh" ]] ; then
            echo "Including library file: ${f}" >>"${LOG_FILE}"
            . "${f}"
        fi
    done

    for f in ${SCRIPT_DIR}/providers/${V4_CFG_CLOUD_PROVIDER}/*.sh ; do
        echo "Including library file: ${f}" >>"${LOG_FILE}"
        . "${f}"
    done

}

do-ssh() {
    
    # Accomodate legacy directory structure
    NEW=$(echo ${V4_CFG_JUMPBOX_SSH_KEY} | grep '/site-config/')
    if [[ "${NEW}" != "/site-config/" ]] ; then
        export V4_CFG_JUMPBOX_SSH_KEY=$( echo "${V4_CFG_JUMPBOX_SSH_KEY}" | sed -e 's|/config/|/site-config/|g' )
    fi

    ssh -i "${V4_CFG_JUMPBOX_SSH_KEY}" ${V4_CFG_DEPLOYMENT_ADMIN_ID}@${V4_CFG_NFS_SVR_NAME}.${V4_CFG_DNS_ZONE}
}

do-command() {
    COMMAND=$(echo "${USER_COMMAND}" | tr '[:upper:]' '[:lower:]')
    do-command-prep
    case "${COMMAND}" in
        build)
            do-build
            update-deployment-config
        ;;
        deploy)
            do-deployment
            update-deployment-config
        ;;
        deployment)
            process-deployment-command
            update-deployment-config
        ;;
        pwd)
            echo "${DEPLOYMENT_DIR}"
        ;;
        ssh)
            do-ssh
        ;;
        help)
            usage
            exit
        ;;
        options)
           display-global-options
        exit
        ;;
        *)
            echo "ERROR: unknown command: ${USER_COMMAND}"
            echo "Run 'viya-deployment --help' for usage."
    esac;
}

validate-parameters() {

    # Did we get any parameters?
    if [ -z ${PARAMS+x} ] ; then
        echo "ERROR: No command specified."
        usage
        exit 1
    else
        # read params into array to support multiple params in future
        read -r -a PARAM_ARRAY <<< "${PARAMS}"
        USER_COMMAND="${PARAM_ARRAY[0]}"

        set-vars-from-config
        do-command
    fi
}

parse-args() {
    while (( "$#" )); do
        case "$1" in
            -a|--account|--cloud-provider-account)
            USER_ARGS[V4_CFG_CLOUD_PROVIDER_ACCOUNT]=$(printf %q "$2")
            shift 2
            ;;
            -c|--config-file)
            USER_ARGS[CONFIG_FILE]="$2"
            shift 2
            ;;
            -b|--blueprint)
            USER_ARGS[V4_CFG_DEPLOYMENT_BLUEPRINT]="$2"
            shift 2
            ;;
            --force-k8s-prereqs)
            USER_ARGS[FORCE_DEPLOY_K8S_PREREQS]="true"
            shift
            ;;
            -g|--resource-group)
            USER_ARGS[V4_CFG_TARGET_RESOURCE_GROUP]="$2"
            shift 2
            ;;
            -i|--infrastructure-only)
            USER_ARGS[INSTALL_VIYA]="false"
            shift
            ;;
            -n|--k8s-namespace)
            USER_ARGS[V4_CFG_K8S_TARGET_NAMESPACE]="$2"
            shift 2
            ;;
            -o|--order-number)
            USER_ARGS[V4_CFG_SAS_ORDER_NUM]="$2"
            shift 2
            ;;
            -p|--cloud-provider|--provider)
            USER_ARGS[V4_CFG_CLOUD_PROVIDER]="$2"
            shift 2
            ;;
            -l|--ldap)
            USER_ARGS[V4_CFG_CONFIGURE_EMBEDDED_LDAP]="true"
            USER_ARGS[V4_CFG_CONFIGURE_SSSD]="true"
            # For now ldap and sssd go together.  that may change depending upon needs once
            # viya is integrated with Azure Active Directory.
            shift
            ;;
            --replicas)
            USER_ARGS[REPLICAS]="$2"
            shift
            ;;
            --scale-nodes)
            USER_ARGS[SCALE_NODES]="true"
            shift
            ;;
            -t|--tls)
            USER_ARGS[V4_CFG_CONFIGURE_TLS]="true"
            shift
            ;;
            --update-network-security-rules)
            USER_ARGS[REFRESH_NETWORK_SECURITY]="true"
            shift
            ;;
            -y)
            USER_ARGS[CMD_LINE_YES]="true"
            shift
            ;;
            -h|--help)
            usage
            exit
            ;;
            --) # end argument parsing
            shift
            break
            ;;
            -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            usage
            exit 1
            ;;
            *) # preserve positional arguments
            PARAMS="$PARAMS $1"
            shift
            ;;
        esac
    done
    validate-parameters
}

create-pod-disruption-budgets() {

    if [ -d "${DEPLOYMENT_DIR}/bundles/default/internal/components" ] ; then
        export COMPONENTS_DIR="${DEPLOYMENT_DIR}/bundles/default/internal/components"
    else
        export COMPONENTS_DIR="${DEPLOYMENT_DIR}/sas-bases/base/components"
    fi

    while read COMPONENT
    do
        if [ -d "${COMPONENTS_DIR}/${COMPONENT}" ] ; then
            RESOURCE_FILE="${COMPONENTS_DIR}/${COMPONENT}/resources.yaml"
            chmod +w "${RESOURCE_FILE}"
            cat <<- EOF >>"${RESOURCE_FILE}"
---
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: ${COMPONENT}
spec:
  minAvailable: 1
  selector:
    matchExpressions:
      - {key: app, operator: In, values: [${COMPONENT}]}
EOF

            chmod -w "${RESOURCE_FILE}"
        fi
    done< <(cd "${COMPONENTS_DIR}"; ls -1)
}
