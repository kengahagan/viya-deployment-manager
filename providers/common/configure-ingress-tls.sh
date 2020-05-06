configure-ingress-tls() {
    echo "processing tls config"

    if [[ ( ${V4_CFG_TLS_CERT} && ${V4_CFG_TLS_KEY} ) && ( "${V4_CFG_CONFIGURE_TLS}" = "true" ) ]] ; then 

      CERT=$(cat ${V4_CFG_TLS_CERT} | base64)
      KEY=$(cat ${V4_CFG_TLS_KEY} | base64)

cat << EOF >nginx-tls.yaml
apiVersion: v1
kind: Secret
type: kubernetes.io/tls
metadata:
  name: aks-ingress-tls
data:
  tls.crt: ${CERT}
  tls.key: ${KEY}
EOF

cat <<-'EOF' > tls_config.yaml 
kind: Ingress
metadata:
  name: wildcard
spec:
  tls:
  - hosts:
    - $(INGRESS_HOST)
    secretName: aks-ingress-tls
EOF

      export TLS_RESOURCE="- nginx-tls.yaml" 
      export TLS_CONFIG=$'- path: tls_config.yaml\n  target:\n    kind: Ingress'
      export URL_PREFIX=https://
      export URL_PORT=:443
    else
      export URL_PREFIX=http://
      export URL_PORT=:80
    fi    
}
