# with the current refactoring in progress i'm being lazy and putting this function
# here...  will determine a more optimal way to structure the code soon
install-viya-logging-and-monitoring() {

    cd "${DEPLOYMENT_DIR}"
    git clone http://gitlab.sas.com/emidev/ops4viya.git

    cd ops4viya
    if kubectl get ns monitoring ; then
		if [[ "${FORCE_DEPLOY_K8S_PREREQS}" = "true" ]] ; then
			VIYA_NS="${V4_CFG_K8S_TARGET_NAMESPACE}" monitoring/bin/remove_monitoring_viya.sh
			monitoring/bin/remove_monitoring_cluster.sh
		else
			return
		fi
    fi

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
 
    sed ${SED_IN_PLACE} -e 's/# storageClassName: nfs-client/storageClassName: nfs-client/g' monitoring/values-prom-operator.yaml
    sed ${SED_IN_PLACE} -e "s/kegaha.viya4.myviya.com/${V4_CFG_K8S_TARGET_NAMESPACE}.${V4_CFG_DNS_HOST}.${V4_CFG_DNS_ZONE}/g" monitoring/user-values-prom-operator.yaml
    monitoring/bin/deploy_monitoring_cluster.sh
    VIYA_NS="${V4_CFG_K8S_TARGET_NAMESPACE}" monitoring/bin/deploy_monitoring_viya.sh

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

deploy-k8s-prereqs() {

    if [[ "${V4_CFG_K8S_INGRESS_TYPE}" == "istio" ]]; then
        install-istio
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
			if [[ "${FORCE_DEPLOY_K8S_PREREQS}" = "true" ]] ; then
				kubectl delete -f config/openldap.yaml
				kubectl delete ns "${V4_CFG_LDAP_NS:-openldap}"
			else
				return
			fi
        fi

        kubectl create namespace "${V4_CFG_LDAP_NS:-openldap}"
        kubectl apply -f config/openldap.yaml -n "${V4_CFG_LDAP_NS:-openldap}"
    else
        log-message "V4_CFG_CONFIGURE_EMBEDDED_LDAP is false - not installing."
    fi

    kubectl create ns ${V4_CFG_K8S_TARGET_NAMESPACE} --save-config
    install-viya-logging-and-monitoring
}


perform-basic-build() {

	while read -r LINE
	do
		NODE="${LINE%|*}"
		USE="${LINE#*|}"
		kubectl label nodes ${NODE} workload.sas.com/class=${USE} --overwrite
		kubectl taint nodes ${NODE} workload.sas.com/class=${USE}:NoSchedule --overwrite
	done<"${CONFIG_DIR}/hosts"
	deploy-k8s-prereqs
}

perform-basic-deployment() {

	#####
	# SAS deployment:
	# - Download the latest Kustomize manifests for the order
	# - Tailor the deployment for this environment
	# - Run Kustomize
	# - Deploy
	#####
	cd "${DEPLOYMENT_DIR}"
	prep-and-run-kustomize

	# Set INSTALL_VIYA to true if it is unset
	INSTALL_VIYA=${INSTALL_VIYA:-true}
    log-message "the value of INSTALL_VIYA is : ${INSTALL_VIYA}"
	if [[ "${INSTALL_VIYA}" = "true" ]] ; then
		kubectl apply -n ${V4_CFG_K8S_TARGET_NAMESPACE} -f base.yaml | tee -a "${LOG_FILE}"

		# poll for ready needs some more work to be reliable..  For now just end.
		#poll-for-ready | tee -a "${LOG_FILE}"
	else
		log-message "INSTALL_VIYA = false.  Will not install."
	fi

	#####
	#
	# To enable the K8s dashboard execute the following
	# kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
	#
	# Then to launch the K8s dashboard issue this command:
	# az aks browse --resource-group $V4_CFG_TARGET_RESOURCE_GROUP --name $V4_CFG_K8S_CLUSTER_NAME
	#
	#####

}
