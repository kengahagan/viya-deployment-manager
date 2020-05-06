
install-istio() {
    log-message "Downloading ISTIO $V4_CFG_ISTIO_VERSION"
    curl -sL "https://github.com/istio/istio/releases/download/$V4_CFG_ISTIO_VERSION/istio-$V4_CFG_ISTIO_VERSION-osx.tar.gz" | tar xz

    kubectl create namespace istio-system --save-config

    log-message "Installing ISTIO"

    export GRAFANA_USERNAME=$(echo -n "grafana" | base64)
    export GRAFANA_PASSPHRASE=$(echo -n "Gr@f4n4PWD40" | base64)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: grafana
  namespace: istio-system
  labels:
    app: grafana
type: Opaque
data:
  username: $GRAFANA_USERNAME
  passphrase: $GRAFANA_PASSPHRASE
EOF

    export KIALI_USERNAME=$(echo -n "kiali" | base64)
    export KIALI_PASSPHRASE=$(echo -n "Ki4l1PWD39" | base64)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kiali
  namespace: istio-system
  labels:
    app: kiali
type: Opaque
data:
  username: $KIALI_USERNAME
  passphrase: $KIALI_PASSPHRASE
EOF

    ./istio-${V4_CFG_ISTIO_VERSION}/bin/istioctl manifest apply \
        --set values.gateways.istio-ingressgateway.enabled=true \
        --set values.gateways.istio-egressgateway.enabled=true  \
        -f istio.aks.yaml \
        | tee -a "${LOG_FILE}"

    kubectl -n istio-system get pods | tee -a "${LOG_FILE}"
    kubectl -n istio-system get svc | tee -a "${LOG_FILE}"


    #####
    #
    # To access various dashboards / metrics / tracing / view mesh configuration:
    #
    # istioctl dashboard grafana
    # istioctl dashboard prometheus
    # istioctl dashboard jaeger
    # istioctl dashboard kiali
    # istioctl dashboard envoy <pod-name>.<namespace>
    #
    #####

}
