install-nginx() {

    if kubectl get ns nginx-ingress ; then
        if [[ "${FORCE_DEPLOY_K8S_PREREQS}" = "true" ]] ; then
            helm uninstall nginx-ingress stable/nginx-ingress \
            --kubeconfig="${V4_CFG_K8S_KUBECONFIG}" \
            --namespace nginx-ingress

            kubectl delete ns nginx-ingress
        else
            return
        fi
    fi

    log-message "Installing nginx-ingress"
    kubectl create ns nginx-ingress

    helm install nginx-ingress stable/nginx-ingress \
        --kubeconfig="${V4_CFG_K8S_KUBECONFIG}" \
        --namespace nginx-ingress \
        --set controller.service.externalTrafficPolicy=Local \
        --set controller.service.sessionAffinity=ClientIP \
        --set controller.replicaCount=1 \
        --set controller.config.use-forwarded-headers=\"true\" \
    | tee -a "${LOG_FILE}"

    kubectl -n nginx-ingress get svc | tee -a "${LOG_FILE}"

}
