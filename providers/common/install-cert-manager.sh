install-cert-manager() {
    
    #TODO: need to determine the version of K8s and apply the correct CRDs.  For now I'm installing the ones I know I need
    # Kubernetes 1.15+
    #$ kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager.crds.yaml

    # Kubernetes <1.15
    #kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager-legacy.crds.yaml \

    if kubectl get ns cert-manager ; then
        helm uninstall cert-manager jetstack/cert-manager \
            --kubeconfig="${V4_CFG_K8S_KUBECONFIG}" \
            --namespace cert-manager \
            | tee -a "${LOG_FILE}"

        kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager.crds.yaml \
        | tee -a "${LOG_FILE}"
    fi

    log-message "Creating Custom Resource Definitions for cert-manager"
    kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager.crds.yaml \
    | tee -a "${LOG_FILE}"

    kubectl create namespace cert-manager
    
    helm repo add jetstack https://charts.jetstack.io --kubeconfig="${V4_CFG_K8S_KUBECONFIG}" | tee -a "${LOG_FILE}"
    helm repo update --kubeconfig="${V4_CFG_K8S_KUBECONFIG}" 
    
    helm install cert-manager jetstack/cert-manager \
    --kubeconfig="${V4_CFG_K8S_KUBECONFIG}" \
    --namespace cert-manager \
    --version v0.14.0 \
    | tee -a "${LOG_FILE}"
    
    log-message "Sleeping 30 seconds to allow cert-manager time to start"
    sleep 30
    
    kubectl apply -n ${V4_CFG_K8S_TARGET_NAMESPACE} -f cert-manager-certframe-integration-install.yaml \
    | tee -a "${LOG_FILE}"

}
