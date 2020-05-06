# with the current refactoring in progress i'm being lazy and putting this function
# here...  will determine a more optimal way to structure the code soon
install-viya-logging-and-monitoring() {

    cd "${DEPLOYMENT_DIR}"
 
    # Check that ssh key var is defined / calculate if not / check if exists
    if [[ "${V4_CFG_JUMPBOX_SSH_KEY:-undefined}" = "undefined" ]] ; then
        if [ -f "${CONFIG_DIR}/.ssh/${V4_CFG_NFS_SVR_NAME}" ] ; then
            export V4_CFG_JUMPBOX_SSH_KEY="${CONFIG_DIR}/.ssh/${V4_CFG_NFS_SVR_NAME}"
        fi
    else
        if [ ! -f "${V4_CFG_JUMPBOX_SSH_KEY}" ] ; then
            log-message "ERROR: The defined jumpbox ssh key does not exist.  Will not deploy kibana."
            unset V4_CFG_JUMPBOX_SSH_KEY
        fi
    fi

    if [ -d ops4viya ] ; then
        rm -rf ops4viya;
    fi

    git clone http://gitlab.sas.com/emidev/ops4viya.git
    cat <<EOF >ops4viya/monitoring/user-values-prom-operator.yaml
# Place overrides for the Prometheus Operator Helm Chart Here

# Prometheus Operator Helm Chart
# https://github.com/helm/charts/blob/master/stable/prometheus-operator/README.md
#
# CRDs
# https://github.com/coreos/prometheus-operator/blob/master/Documentation/api.md
#
# Default Values
# https://github.com/helm/charts/blob/master/stable/prometheus-operator/values.yaml

# Sample ingress configuration
# NOTE: Edit hostnames and ingress port

 prometheus:
   service:
     type: ClusterIP
     nodePort: null
   ingress:
     enabled: true
     annotations:
       kubernetes.io/ingress.class: nginx
       nginx.ingress.kubernetes.io/rewrite-target: /$2
     hosts:
     - ${V4_CFG_INGRESS_NAME}
     path: /prometheus(/|$)(.*)
   prometheusSpec:
     externalUrl: http://${V4_CFG_INGRESS_NAME}/prometheus

 alertmanager:
   service:
     type: ClusterIP
     nodePort: null
   ingress:
     enabled: true
     annotations:
       kubernetes.io/ingress.class: nginx
       nginx.ingress.kubernetes.io/rewrite-target: /$2
     hosts:
     - ${V4_CFG_INGRESS_NAME}
     path: /alertmanager(/|$)(.*)

 grafana:
   service:
     type: ClusterIP
     nodePort: null
   ingress:
     enabled: true
     annotations:
       kubernetes.io/ingress.class: nginx
       nginx.ingress.kubernetes.io/rewrite-target: /
     hosts:
     - grafana-${V4_CFG_INGRESS_NAME}
     path: /

 prometheus-node-exporter:
   service:
     # Override the default port of 9100 to avoid potential conflicts
     port: 9110
     targetPort: 9110
   # Allow pod to be scheduled on master nodes that otherwise
   # wouldn't schedule normal pods
   tolerations:
   - key: node-role.kubernetes.io/master
     effect: NoSchedule
   - key: workload.sas.com/class
     operator: Exists
     effect: NoSchedule
EOF

    cat <<EOF >>ops4viya/monitoring/values-pushgateway.yaml

persistentVolume:
  enabled: true
  storageClass: nfs-client
EOF

    cat <<EOF >>ops4viya/logging/fb/fluent-bit_helm_values_open.yaml
- key: workload.sas.com/class
  operator: Exists
  effect: NoSchedule
EOF
    #tar xf "${CONFIG_DIR}/ops4viya.tgz"
    cd ops4viya
    if kubectl get ns monitoring ; then
        VIYA_NS="${V4_CFG_K8S_TARGET_NAMESPACE}" monitoring/bin/remove_monitoring_viya.sh
        monitoring/bin/remove_monitoring_cluster.sh
    fi

    sed ${SED_IN_PLACE} -e 's/# storageClassName: nfs-client/storageClassName: nfs-client/g' monitoring/values-prom-operator.yaml
    sed ${SED_IN_PLACE} -e "s/kegaha.viya4.myviya.com/${V4_CFG_K8S_TARGET_NAMESPACE}.${V4_CFG_DNS_HOST}.${V4_CFG_DNS_ZONE}/g" monitoring/user-values-prom-operator.yaml
    monitoring/bin/deploy_monitoring_cluster.sh
    VIYA_NS="${V4_CFG_K8S_TARGET_NAMESPACE}" monitoring/bin/deploy_monitoring_viya.sh

    # Have let Greg Smith know that the mechanics of deployment need to 
    # support not having direct curl access to the nodes but for now we're going 
    # to SCP to the jumpbox and run the monitoring deployment from there.

    cd "${DEPLOYMENT_DIR}"
    
    sed ${SED_IN_PLACE} -e 's/storageClassName: alt-storage/storageClassName: nfs-client/g' logging/es/storage/elasticsearch_create_master_pv.ALL.yaml
    sed ${SED_IN_PLACE} -e 's/storageClassName: alt-storage/storageClassName: nfs-client/g' logging/es/storage/elasticsearch_create_master_pvc.ALL.yaml
    sed ${SED_IN_PLACE} -e 's/#storageClass: alt-storage/storageClass: nfs-client/g' logging/es/odfe/es_helm_values_open.yaml
    logging/bin/deploy_logging_open.sh

    cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    cadence.sas.com/display-name: ""
    cadence.sas.com/name: ""
    cadence.sas.com/release: ""
    cadence.sas.com/version: ""
    nginx.ingress.kubernetes.io/proxy-body-size: 2048m
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: nginx
    sas.com/component-name: sas-logging-kibana
  labels:
    app.kubernetes.io/name: sas-logging-kibana
    sas.com/admin: namespace
    sas.com/deployment: sas-viya
  name: sas-logging-kibana
  namespace: logging
spec:
  rules:
  - host: kibana-${V4_CFG_INGRESS_NAME}
    http:
      paths:
      - backend:
          serviceName: v4m-es-kibana-svc
          servicePort: 5601
        path: /
EOF

}

add-aks-nodepool() {
    # This function requires 5 arguments
    # $1 = name of requested node pool
    # $2 = requested vm size
    # $3 = min node count
    # $4 = max node count
    # $5 = initial node count
    # if a 6th argument is provided it is used for node labels

    if [[ $# -lt 5 ]] ; then
        log-message "ERROR: add-aks-nodepool called with insufficient arguments."
        log-message "       $# arguments passed - 5 are required.  Arguments:"
        log-message "       $@"
        exit 1
    fi

    if [[ "$6" != "" ]] ; then
        NP_LABELS="--labels """$6""" "
    else
        NP_LABELS=""
    fi

    if [[ "$1" = "" ]] ; then
        log-message "ERROR: add-aks-nodepool called without name."
        exit 1
    else
        export NP_NAME="$1"
        if [[ "$1" = "cas" ]] ; then
            # TODO deal with backup controller
            if [[ "V4_CFG_CAS_SERVER_TYPE" = "smp" ]] ; then
                export V4_CFG_CAS_WORKER_QTY="0"
                export V4_CFG_CAS_NODE_COUNT="1"
            else
                export V4_CFG_CAS_WORKER_QTY="${V4_CFG_CAS_WORKER_QTY:-"3"}"
                export V4_CFG_CAS_NODE_COUNT=$((${V4_CFG_CAS_WORKER_QTY} + 1))
            fi
            export V4_CFG_CAS_MAX_NODE_COUNT=$((${V4_CFG_CAS_NODE_COUNT} + ${4}))
        else 
            export V4_CFG_CAS_NODE_COUNT=$5
            export V4_CFG_CAS_MAX_NODE_COUNT=$4
        fi
    fi

 	if NP_STATUS=$(az aks nodepool show --name "${NP_NAME}" --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query name -o tsv 2>&1 ); then
        log-message "AKS cluster ${V4_CFG_K8S_CLUSTER_NAME} already has a node pool named ${NP_NAME}.  Will use as-is."
    else
        log-message "Creating a node pool named ${NP_NAME} in cluster ${V4_CFG_K8S_CLUSTER_NAME}."
        az aks nodepool add \
           --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} \
           --name ${NP_NAME} \
           --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} \
           --mode User \
           --enable-cluster-autoscaler \
           --node-vm-size $2 \
           --min-count $3 \
           --max-count ${V4_CFG_CAS_MAX_NODE_COUNT} \
           --node-count ${V4_CFG_CAS_NODE_COUNT} \
           --node-taints "workload.sas.com/class=${NP_NAME}:NoSchedule" \
           --vnet-subnet-id ${K8S_SUBNET_ID} \
           ${NP_LABELS} \
           >>"${LOG_FILE}" 

        log-message "Node pool creation completed for ${NP_NAME} in cluster ${V4_CFG_K8S_CLUSTER_NAME}.  Node count: ${V4_CFG_CAS_NODE_COUNT} Max node count: ${V4_CFG_CAS_MAX_NODE_COUNT} "
    fi
}

deploy-k8s-prereqs() {
    az aks get-credentials --name ${V4_CFG_K8S_CLUSTER_NAME} --overwrite-existing --file "${V4_CFG_K8S_KUBECONFIG}"

    if [[ "${V4_CFG_K8S_INGRESS_TYPE}" == "istio" ]]; then
        install-istio
    elif [[ "${V4_CFG_K8S_INGRESS_TYPE}" == "azure" ]]; then
        # see https://github.com/Azure/application-gateway-kubernetes-ingress/
        install-azure-AGIC
    else
        install-nginx
    fi

    if [[ "${V4_CFG_CONFIGURE_TLS}" = "true" ]] ; then
        #####
        # Install cert-manager to support TLS inside the cluster
        #####
        install-cert-manager
    else
        log-message "V4_CFG_CONFIGURE_TLS is false - not installing cert-manager"
    fi

    install-nfs-client-pv-mgr

    if [[ "${V4_CFG_CONFIGURE_EMBEDDED_LDAP}" = "true" ]] ; then
        # temporary work around until we have integration with AAD working
        if kubectl get ns ${V4_CFG_LDAP_NS:-openldap} ; then
            kubectl delete -f config/openldap.yaml
            kubectl delete ns "${V4_CFG_LDAP_NS:-openldap}"
        fi

        kubectl create namespace "${V4_CFG_LDAP_NS:-openldap}"
        kubectl apply -f config/openldap.yaml -n "${V4_CFG_LDAP_NS:-openldap}"
    else
        log-message "V4_CFG_CONFIGURE_EMBEDDED_LDAP is false - not installing."
    fi

    kubectl create ns ${V4_CFG_K8S_TARGET_NAMESPACE} --save-config
    install-viya-logging-and-monitoring
}

setup-aks-cluster() {
    #####
    #
    # This will get someone going for now... will next set up multiple node pools for 
    # services / pets / CAS / Compute
    # 
    # use --node-resource-group to set name of initial cluster and use az aks nodepool add
    # https://docs.microsoft.com/en-us/azure/aks/use-multiple-node-pools to add more
    # 
    #####
    log-message "Creating AKS cluster"
    #TODO: need to support registry being provided...
    if [[ "${V4_CFG_K8S_AUTHORIZED_NETWORKS}" = "" ]] ; then
        log-message "authorized networks not defined... setting to jumpbox IP address(${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS})."
        export V4_CFG_K8S_AUTHORIZED_NETWORKS="${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS}"
    else
        log-message "AKS API Server authorized IP ranges: ${V4_CFG_K8S_AUTHORIZED_NETWORKS}.  Adding jumpbox IP address (${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS})."
        export V4_CFG_K8S_AUTHORIZED_NETWORKS="${V4_CFG_K8S_AUTHORIZED_NETWORKS},${V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS}"
        log-message "AKS API Server authorized IP ranges: ${V4_CFG_K8S_AUTHORIZED_NETWORKS}"
    fi
    
 	if AKS_STATUS=$(az aks show --name ${V4_CFG_K8S_CLUSTER_NAME} --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} --query name -o tsv 2>&1 ); then
            log-message "AKS deployment ${V4_CFG_K8S_CLUSTER_NAME} exists.  Will use as-is."
            az aks get-credentials --name ${V4_CFG_K8S_CLUSTER_NAME} --overwrite-existing --file "${V4_CFG_K8S_KUBECONFIG}"
    else
        # have removed --enable-addons monitoring \ for now given ops4viya
        # consider adding Azure monitoring back as an option later
        az aks create \
            --resource-group  ${V4_CFG_TARGET_RESOURCE_GROUP} \
            --node-resource-group ${AKS_PRI_NODEPOOL_NM} \
            --name ${V4_CFG_K8S_CLUSTER_NAME} \
            --node-vm-size ${V4_CFG_VM_SKU_K8S_SYSTEM_NP} \
            --node-count 2 \
            --min-count 1 \
            --max-count 5 \
            --enable-cluster-autoscaler \
            --nodepool-name system \
            --network-plugin kubenet \
            --service-cidr 10.0.0.0/16 \
            --dns-service-ip 10.0.0.10 \
            --pod-cidr 10.244.0.0/16 \
            --docker-bridge-address 172.17.0.1/16 \
            --vnet-subnet-id ${SUBNET_ID} \
            --service-principal ${V4_CFG_CLOUD_PROVIDER_SP_APP_ID} \
            --client-secret ${SP_PWD} \
            --api-server-authorized-ip-ranges ${V4_CFG_K8S_AUTHORIZED_NETWORKS} \
            --generate-ssh-keys \
            >>"${LOG_FILE}"

        # set system mode for the system node pool
        az aks nodepool update \
           --resource-group ${V4_CFG_TARGET_RESOURCE_GROUP} \
           --cluster-name ${V4_CFG_K8S_CLUSTER_NAME} \
           --name system \
           --mode system \
           >>"${LOG_FILE}"

        if [[ "${V4_CFG_MANAGE_DNS}" = "true" ]] ; then
            export V4_CFG_INGRESS_NAME="${V4_CFG_K8S_TARGET_NAMESPACE}.${V4_CFG_DNS_HOST}.${V4_CFG_DNS_ZONE}"
        else
            #if we're not managing DNS then pull the public hostname for the cluster
            #Not sure what we will do about the wildcard DNS name though... will have to look into that.
            # TODO FIX THIS:
            export V4_CFG_INGRESS_NAME="${V4_CFG_K8S_TARGET_NAMESPACE}.${2}"
        fi

        export AKS_NODE_NSG_NAME=$(az network nsg list -g ${AKS_PRI_NODEPOOL_NM} --query "[].name | [0]" -o tsv)
        # aparently Azure can sometimes have a little delay before the NSG is available...
       	until [[ "${AKS_NODE_NSG_NAME}" != "" ]] ; do
            log-message "Waiting for AKS NSG to be available..."
            sleep 10
            export AKS_NODE_NSG_NAME=$(az network nsg list -g ${AKS_PRI_NODEPOOL_NM} --query "[].name | [0]" -o tsv)
    	done

        # if we're re-creating the cluster then we will need to refresh the network security rules.
        export REFRESH_NETWORK_SECURITY="true"
        log-message "Applying rules to the AKS NSG (${AKS_NODE_NSG_NAME})"
        create-nsg-rules "${AKS_NODE_NSG_NAME}" "${AKS_PRI_NODEPOOL_NM}" 

        export ROUTE_TABLE=$(az network route-table list -g ${AKS_PRI_NODEPOOL_NM} --query "[].id | [0]" -o tsv)
        export AKS_NODE_SUBNET_ID=$(az network vnet subnet show -g ${V4_CFG_TARGET_RESOURCE_GROUP} --name "${VNET_NAME}-aks-subnet" --vnet-name ${VNET_NAME} --query id -o tsv)
        export AKS_NODE_NSG=$(az network nsg list -g ${AKS_PRI_NODEPOOL_NM} --query "[].id | [0]" -o tsv)

        log-message "Associating AKS node route table with AKS subnet..."
        # Update the Subnet
        az network vnet subnet update \
        --route-table ${ROUTE_TABLE} \
        --network-security-group ${AKS_NODE_NSG} \
        --ids ${AKS_NODE_SUBNET_ID} \
        >>"${LOG_FILE}"

        deploy-k8s-prereqs
    fi

    if [ "${FORCE_DEPLOY_K8S_PREREQS:-false}" = "true" ] ; then
        deploy-k8s-prereqs
    fi

    get-ingress-ip
    create-or-replace-dns-A-record "${V4_CFG_DNS_HOST}" "${INGRESS_IP_ADDR}"
    create-or-replace-dns-wildcard-cname "${V4_CFG_DNS_HOST}"

    # Need to get the K8s subnet id if we are adding a node pool to a k8s environment that has been up
    if [[ "${K8S_SUBNET_ID}" = "" ]] ; then
        export K8S_SUBNET_ID=$(az network vnet subnet show -g ${V4_CFG_TARGET_RESOURCE_GROUP}  --vnet-name ${VNET_NAME} --name "${VNET_NAME}-aks-subnet" --query "id" -o tsv )
    fi

    # when HA option is provided later will need to revisit parameters.
    # add a node pool for running the stateless services
    if [[ "${V4_CFG_VM_SKU_K8S_STATELESS_NP:-NO}" != "NO" ]] ; then
        add-aks-nodepool stateless ${V4_CFG_VM_SKU_K8S_STATELESS_NP} 1 5 1 "workload.sas.com/class=stateless" &
    fi

    # add a node pool for running the stateful services
    if [[ "${V4_CFG_VM_SKU_K8S_STATEFUL_NP:-NO}" != "NO" ]] ; then
        add-aks-nodepool stateful ${V4_CFG_VM_SKU_K8S_STATEFUL_NP} 1 3 1 "workload.sas.com/class=stateful" &
    fi

    # add a node pool for running compute
    if [[ "${V4_CFG_VM_SKU_K8S_COMPUTE_NP:-NO}" != "NO" ]] ; then
        add-aks-nodepool compute ${V4_CFG_VM_SKU_K8S_COMPUTE_NP} 1 5 1 "workload.sas.com/class=compute launcher.sas.com/prepullImage=sas-programming-environment" &
    fi

    # add a node pool for running CAS
    if [[ "${V4_CFG_VM_SKU_K8S_CAS_NP:-NO}" != "NO" ]] ; then
        add-aks-nodepool cas ${V4_CFG_VM_SKU_K8S_CAS_NP} 1 5 1 "workload.sas.com/class=cas" &
    fi

    # wait for all background nodepool creation submissions to complete.
    wait
}
