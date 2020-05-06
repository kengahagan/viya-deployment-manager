get-ingress-ip() {

    if [[ "${V4_CFG_K8S_INGRESS_TYPE}" == "istio" ]]; then
        echo "I don't know how to do that yet"
        #TODO: Teach how to deal with istio ingress
    else
        INGRESS_IP_ADDR=$( kubectl -n nginx-ingress get svc | grep LoadBalancer | awk '{ print $4 }' )

        until [[ "${INGRESS_IP_ADDR}" != "<pending>" && "${INGRESS_IP_ADDR}" != "" ]] ; do
            sleep 30
            INGRESS_IP_ADDR=$( kubectl -n nginx-ingress get svc | grep LoadBalancer | awk '{ print $4 }' ) 
            log-message "nginx-ingress IP Address is ${INGRESS_IP_ADDR}. "
        done
    fi
}
