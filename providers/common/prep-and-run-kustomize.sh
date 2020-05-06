set-bundle-paths() {
    if [[ "${V4_CFG_ORDER_TYPE}" = "cadence" ]] ; then
      BUNDLE_ROOT="sas-bases"
      BASES_LOC="${BUNDLE_ROOT}/base"
    else
      BUNDLE_ROOT="bundles/default"
      BASES_LOC="${BUNDLE_ROOT}/bases/sas"
    fi
}

get-kustomize-bundle() {


  if [ -f "${CONFIG_DIR}/kustomize-bundle-${V4_CFG_SAS_ORDER_NUM}.tgz" ] ; then
    log-message "NOTE: Using existing kustomize manifest content..."
  else
    # Let's see if this is a new order:
    BUNDLE_URI="https://apigateway-test.sas.com/reofs_internal/orders/${V4_CFG_SAS_ORDER_NUM}/subOrders/70180938/deploymentAssets"
    # https://apigateway-test.sas.com/reofs_internal/orders/99X99X/subOrders/70180938/cadenceNames/<cadence name>/cadenceVersions/<cadence version>/deploymentAssets

    wget  -O "${CONFIG_DIR}/kustomize-bundle-${V4_CFG_SAS_ORDER_NUM}.tgz" --header "X-API-KEY: ${MY_SAS_RE_API_KEY}" \
          --header "currentuser-mail: ${V4_CFG_SAS_PROFILE_ID}" \
          --header "Client-Application-User: ${V4_CFG_SAS_USER_ID}" ${BUNDLE_URI} 
    if [[ $? -eq 0 ]] ; then
       V4_CFG_ORDER_TYPE="cadence"
       return
    else
       log-message "Did not find order to be a cadence order.  Trying legacy ship event orders."
       BUNDLE_URI="https://apigateway-stage.sas.com/reofs_internal/orders/${V4_CFG_SAS_ORDER_NUM}/subOrders/70180938/deploymentAssets"
       wget  -O "${CONFIG_DIR}/kustomize-bundle-${V4_CFG_SAS_ORDER_NUM}.tgz" --header "X-API-KEY: ${MY_SAS_RE_API_KEY}" \
             --header "currentuser-mail: ${V4_CFG_SAS_PROFILE_ID}" \
             --header "Client-Application-User: ${V4_CFG_SAS_USER_ID}" ${BUNDLE_URI} 
      if [[ $? -eq 0 ]] ; then
          log-message "Found order to be a legacy order"
          V4_CFG_ORDER_TYPE="legacy"
      else
          log-message "The order could not be found.  Can not continue."
          exit 1
      fi
    fi

  fi

}

prep-for-mas() {
  # MAS needs a common ASTORE directory 
cat << EOF > site-config/astores-volume.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: astores
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: nfs-client
EOF

cat << EOF > site-config/mas-python-transformer.yaml
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: mas-python-transformer
patch: |-
  # Add python volume
  - op: add
    path: /spec/template/spec/volumes/-
    value: { name: python-volume, nfs: { path: /export/bin/nfsviyapython, server: ${NFS_SVR} } }

  # Add mount path for python
  - op: add
    path: /spec/template/spec/containers/0/volumeMounts/-
    value:
      name: python-volume
      mountPath: /python
      readOnly: true

  # Add python-config configMap
  - op: add
    path: /spec/template/spec/containers/0/envFrom/-
    value:
      configMapRef:
        name: sas-open-source-config-python

target:
  group: apps
  kind: Deployment
  name: sas-microanalytic-score
  version: v1
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: cas-python-transformer
patch: |-
  # Add python volume
  - op: add
    path: /spec/controllerTemplate/spec/volumes/-
    value: { name: python-volume, nfs: { path: /export/bin/nfsviyapython, server: ${NFS_SVR} } }

  # Add mount path for python
  - op: add
    path: /spec/controllerTemplate/spec/containers/0/volumeMounts/-
    value:
      name: python-volume
      mountPath: /python
      readOnly: true

  # Add python-config configMap
  - op: add
    path: /spec/controllerTemplate/spec/containers/0/envFrom/-
    value:
      configMapRef:
        name: sas-open-source-config-python

target:
  group: viya.sas.com
  kind: CASDeployment
  name: .*
  version: v1alpha1
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: launcher-job-python-transformer
patch: |-
  # Add python volume
  - op: add
    path: /template/spec/volumes/-
    value: { name: python-volume, nfs: { path: /export/bin/nfsviyapython, server: ${NFS_SVR} } }

  # Add mount path for python
  - op: add
    path: /template/spec/containers/0/volumeMounts/-
    value:
      name: python-volume
      mountPath: /python
      readOnly: true

  # Add python-config configMap
  - op: add
    path: /template/spec/containers/0/envFrom/-
    value:
      configMapRef:
        name: sas-open-source-config-python

target:
  kind: PodTemplate
  name: sas-launcher-job-config
  version: v1
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: compute-job-python-transformer
patch: |-
  # Add python volume
  - op: add
    path: /template/spec/volumes/-
    value: { name: python-volume, nfs: { path: /export/bin/nfsviyapython, server: ${NFS_SVR} } }

  # Add mount path for python
  - op: add
    path: /template/spec/containers/0/volumeMounts/-
    value:
      name: python-volume
      mountPath: /python
      readOnly: true

  # Add python-config configMap
  - op: add
    path: /template/spec/containers/0/envFrom/-
    value:
      configMapRef:
        name: sas-open-source-config-python

target:
  kind: PodTemplate
  name: sas-compute-job-config
  version: v1
EOF

  export MAS_CONFIG_MAP_GENERATOR=$'- name: sas-open-source-config-python\n  literals:\n  - MAS_PYPATH=/python/bin/python3\n  - MAS_M2PATH=/opt/sas/viya/home/SASFoundation/misc/embscoreeng/mas2py.py\n  - DM_PYTHONHOME=/python/bin'

  # TODO: This works for inside SAS - Probably need to put config variables in for path to the python install.
  if [ ! -f python.tgz ] ; then
    cd /net/edmtest-util.hes.sashq-d.openstack.sas.com/share/
    tar czf "${DEPLOYMENT_DIR}/python.tgz" nfsviyapython
    cd ${DEPLOYMENT_DIR}
  fi
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "${V4_CFG_JUMPBOX_SSH_KEY}" python.tgz "${V4_CFG_DEPLOYMENT_ADMIN_ID}@${V4_CFG_NFS_SVR_NAME}.${V4_CFG_DNS_ZONE}:~/"
  ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "${V4_CFG_JUMPBOX_SSH_KEY}" ${V4_CFG_DEPLOYMENT_ADMIN_ID}@${V4_CFG_NFS_SVR_NAME}.${V4_CFG_DNS_ZONE} "sudo mkdir -p /export/bin; cd /export/bin; sudo tar xf /home/${V4_CFG_DEPLOYMENT_ADMIN_ID}/python.tgz"
  cp "${BUNDLE_ROOT}/examples/sas-microanalytic-score/astores/astores-transformer.yaml" site-config/
  chmod 644 site-config/astores-transformer.yaml

  export MAS_RESOURCES="- site-config/astores-volume.yaml"
  export MAS_TRANSFORMER=$'- site-config/astores-transformer.yaml\n- site-config/mas-python-transformer.yaml'
}

prep-and-run-kustomize() {

cd "${DEPLOYMENT_DIR}"

get-kustomize-bundle
set-bundle-paths
tar xf "${CONFIG_DIR}/kustomize-bundle-${V4_CFG_SAS_ORDER_NUM}.tgz"
create-pod-disruption-budgets


case "${V4_CFG_CLOUD_PROVIDER}" in 
  azure)
    NFS_SVR="${V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS}" 
  ;;
  custom)
    NFS_SVR="${V4_CFG_NFS_SVR_NAME}"
  ;;
esac

if [ -d "${COMPONENTS_DIR}/sas-microanalytic-score" ] ; then
    prep-for-mas
fi

#curl -sk https://gitlab.sas.com/convoy/devops/kustomizations/-/archive/master/kustomizations-master.tar.gz | tar  -xz --strip-components=1

configure-ingress-tls

# For those who like to spell it with an 'a'
if [ -f config/sitedefault.yaml ] ; then
   export CONSUL_CONFIG=$'- name: sas-consul-config\n  behavior: merge\n  files:\n  - SITEDEFAULT_CONF=site-config/sitedefault.yaml'
   CONSUL_CONFIG_SET="true"
else
   export CONSUL_CONFIG=""
   CONSUL_CONFIG_SET="false"
fi

# For those who are more oriented to Viya 3.5 and which to save the extra char...
if [[ -f config/sitedefault.yml ]] ; then
   export CONSUL_CONFIG=$'- name: sas-consul-config\n  behavior: merge\n  files:\n  - SITEDEFAULT_CONF=site-config/sitedefault.yml'
else
  if [[ "${CONSUL_CONFIG_SET}" = "false" ]] ; then
    export CONSUL_CONFIG=""
  fi
fi

if [[ "${V4_CFG_CONFIGURE_SSSD}" = "true" ]] ; then

cat << EOF > compsrv-sssd.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compsrv
spec:
  template:
    spec:
      containers:
      - name: sssd
        volumeMounts:
          - name: sssd-config
            mountPath: "/etc/sssd"
      volumes:
      - name: sssd-config
        configMap:
          name: sas-sssd-config
          items:
          - key: SSSD_CONF
            path: sssd.conf
            mode: 0600
EOF

  SSSD_RESOURCE="- site-config/sssd-configmap.yaml"
  SSSD_PATCH="- path: site-config/compsrv-sssd-nfs.yaml"
  #TODO: break sssd and nfs mounts into two patches.  No reason to be the same.
fi

if [[ "${V4_CFG_CONFIGURE_TLS}" = "true" ]] ; then
  export TLS_RESOURCE=${TLS_RESOURCE}$'\n- ${BUNDLE_ROOT}/overlays/network/ingress/security\n- site-config/consul-and-cas-ingress.yaml\n'
  export TLS_TRANSFORMS=$'- ${BUNDLE_ROOT}/overlays/network/ingress/security/patches/product-tls-patches.yaml\n- site-config/networking-k8s-io-ingress-patch.yaml\n- ${BUNDLE_ROOT}/overlays/network/ingress/security/patches/backend-tls-patches.yaml\n- ${BUNDLE_ROOT}/examples/security/user-patches-tls.yaml'
  export TLS_GENERATORS=$'generators:\n- ${BUNDLE_ROOT}/examples/security/user-custom-ingress-cert-generator.yaml\n- ${BUNDLE_ROOT}/examples/security/additional-ca-certificates-configmap.yaml\n- ${BUNDLE_ROOT}/overlays/network/ingress/security/generator-merges/backend-tls-generator-merges.yaml'
else
  export TLS_RESOURCE=""
fi

CAS_AVAIL_RAM=$( kubectl get node --selector=workload.sas.com/class=cas --output=custom-columns=AvailMem:.status.allocatable.memory --no-headers | head -n 1 )
CAS_AVAIL_RAM_UNITS=${CAS_AVAIL_RAM: -2}
CAS_AVAIL_RAM=${CAS_AVAIL_RAM%${CAS_AVAIL_RAM_UNITS}}
# Assuming for now that units are always Ki - this is probably a disaster waiting to happen so need to assess further later
# Assuming that for now by the time we are ready to deploy that any other processes have been started (logging / monitoring)
# and that all remaining RAM is available to CAS.  Furthermore assuming that all nodes are uniform / have uniform available RAM
# of course rarely are things perfectly equal so let's start with 512k off the top as buffer
CAS_AVAIL_RAM=$(( CAS_AVAIL_RAM - 512 ))

# We're going to allocate 500Mi of RAM to the backup agent
CAS_BKUP_AGENT_RAM=$(( 500 * 1024 ))

CAS_AVAIL_RAM=$(( ${CAS_AVAIL_RAM} - ${CAS_BKUP_AGENT_RAM} ))
#put in a variable that will be recorded to the defaults file 
V4_CFG_CAS_RAM_PER_NODE="${CAS_AVAIL_RAM}${CAS_AVAIL_RAM_UNITS}"

# All CAS nodes in the default cluster will be uniform - get number of vCPU on the first host
CAS_HOST_VCPUS=$( kubectl get node --selector=workload.sas.com/class=cas --output=custom-columns=AvailCPU:.status.capacity.cpu --no-headers | head -n 1 )
# Will allocate 500m to to the backup agent and give vCPU - 1 to the CAS process
CAS_HOST_VCPUS=$(( ${CAS_HOST_VCPUS} - 1 ))
V4_CFG_CAS_CORES_PER_NODE=${CAS_HOST_VCPUS}

# Thank you to Matthias Ender who provided this recipe
# create a new secret and put the payload into a variable 
# - this does not really create secret on the server:
# notice the --dry-run option
CR_SAS_COM_SECRET="$(kubectl create secret docker-registry cr-access \
  --docker-server=cr.sas.com \
  --docker-username=$SAS_CR_USERID \
  --docker-password=$SAS_CR_PASSWORD \
  --dry-run -o json | jq -r '.data.".dockerconfigjson"')"

#kubectl -n ${V4_CFG_K8S_TARGET_NAMESPACE} create secret docker-registry regcred \
#   --docker-server=cr.sas.com \
#   --docker-username=$SAS_CR_USERID \
#   --docker-password=$SAS_CR_PASSWORD 

# put the payload decoded into a file
echo -n $CR_SAS_COM_SECRET | base64 --decode > cr_sas_com_access.json

cat << EOF > kustomization.yaml
namespace: ${V4_CFG_K8S_TARGET_NAMESPACE}
resources:
- ${BASES_LOC}
- ${BUNDLE_ROOT}/overlays/network/${V4_CFG_K8S_INGRESS_TYPE}
- ${BUNDLE_ROOT}/overlays/cas-${V4_CFG_CAS_SERVER_TYPE:-smp}
${TLS_RESOURCE}
${SSSD_RESOURCE}
${MAS_RESOURCES}
transformers:
- ${BUNDLE_ROOT}/overlays/external-postgres/external-postgres-transformer.yaml
- site-config/cas-transformer.yaml
${TLS_TRANSFORMS}
${MAS_TRANSFORMER}
- ${BUNDLE_ROOT}/overlays/required/transformers.yaml
${TLS_GENERATORS}
configMapGenerator:
- name: ingress-input
  behavior: merge
  literals:
  - INGRESS_HOST=${V4_CFG_INGRESS_NAME}
- name: sas-shared-config
  behavior: merge
  literals:
  - SPRING_DATASOURCE_USERNAME=${V4_CFG_POSTGRES_ADMIN_LOGIN}
  - SPRING_DATASOURCE_PASSWORD=${V4_CFG_POSTGRES_PASSWORD}
  - SAS_URL_SERVICE_TEMPLATE=${URL_PREFIX}${V4_CFG_INGRESS_NAME}${URL_PORT}
- name: postgres-config
  literals:
  - DATABASE_HOST=${V4_CFG_POSTGRES_FQDN}
  - DATABASE_PORT=5432
  - DATABASE_NAME=SharedServices
  - EXTERNAL_DATABASE="true"
${CONSUL_CONFIG}
${MAS_CONFIG_MAP_GENERATOR}
secretGenerator:
- name: postgres-sas-user
  literals:
  - username=${V4_CFG_POSTGRES_ADMIN_LOGIN}
  - password=${V4_CFG_POSTGRES_PASSWORD}
- name: sas-image-pull-secrets
  behavior: replace
  type: kubernetes.io/dockerconfigjson
  files:
  - .dockerconfigjson=cr_sas_com_access.json

patchesJson6902:
- target:
    group: apps
    version: v1
    kind: StatefulSet
    name: sas-cacheserver
  path: site-config/ss-storclass.yaml

- target:
    group: apps
    version: v1
    kind: StatefulSet
    name: sas-consul-server
  path: site-config/ss-storclass.yaml

- target:
    group: apps
    version: v1
    kind: StatefulSet
    name: sas-rabbitmq-server
  path: site-config/rabbit-transformer.yaml

- path: site-config/compute-template-nfs.yaml
  target:
    kind: PodTemplate
    name: sas-launcher-job-config
    version: v1

patches:
- path: site-config/custom_classname.yaml
  target:
    kind: PersistentVolumeClaim
- path: site-config/compsrv-sssd.yaml
- path: site-config/compsrv-nfs.yaml

- path: site-config/stateless-affinity.yaml
  target:
    kind: Deployment
    labelSelector: sas.com/deployment-base in (spring, golang)

- path: site-config/stateless-affinity.yaml
  target:
    kind: Deployment
    name: sas-cas-operator

- path: site-config/stateful-affinity.yaml
  target:
    kind: Deployment
    annotationSelector: sas.com/component-name in (sas-data-server-utility)

- path: site-config/stateful-affinity.yaml
  target:
    kind: StatefulSet
    annotationSelector: sas.com/component-name in (sas-consul-server, sas-rabbitmq-server, sas-cacheserver)

- path: site-config/compute-affinity.yaml
  target:
    kind: Deployment
    name: compsrv

- path: site-config/compute-podtemplate-affinity.yaml
  target:
    kind: PodTemplate
    name: .*

- path: site-config/cas-affinity.yaml
  target:
    group: viya.sas.com
    kind: CASDeployment
    name: .*
    version: v1alpha1

${TLS_CONFIG}
EOF

### NEED TO DEAL WITH STORAGE CLASS - set default to nfs-client ###
cat << EOF > site-config/custom_classname.yaml
kind: PersistentStorageClass
metadata:
  name: wildcard
spec:
  storageClassName: nfs-client
EOF

cat << EOF > site-config/ss-storclass.yaml
- op: add
  path: /spec/volumeClaimTemplates/0/spec/storageClassName
  value: nfs-client
EOF

cat <<- EOF > site-config/rabbit-transformer.yaml
- op: replace
  path: /spec/template/spec/containers/0/resources/limits/memory
  value:
    2Gi
EOF

cat <<- EOF >site-config/compsrv-nfs.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compsrv
spec:
  template:
    spec:
      containers:
      - name: compsrv
        volumeMounts:
        - mountPath: /mnt/data
          name: nfs-data
        - mountPath: /mnt/homes
          name: nfs-homes
      volumes:
      - name: nfs-data
        nfs:
          server: ${NFS_SVR}
          path: /export/data
      - name: nfs-homes
        nfs:
          server: ${NFS_SVR}
          path: /export/homes
EOF

cat <<- EOF > site-config/compute-template-nfs.yaml
  - op: add
    path: /template/spec/containers/0/volumeMounts/-
    value:
      mountPath: /mnt/data
      name: nfs-data
  - op: add
    path: /template/spec/containers/0/volumeMounts/-
    value:
      mountPath: /mnt/homes
      name: nfs-homes
  - op: add
    path: /template/spec/volumes/-
    value:
      name: nfs-data
      nfs:
        server: ${NFS_SVR}
        path: /export/data
  - op: add
    path: /template/spec/volumes/-
    value:
      name: nfs-homes
      nfs:
        server: ${NFS_SVR}
        path: /export/homes
EOF

# set up the cas-transformer.yaml file if it hasn't been passed in
if [ ! -f site-config/cas-transformer.yaml ] ; then

cat <<- EOF >> site-config/cas-transformer.yaml
# Add additional mounts needed to conform to deployment pattern
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: cas-add-mount
patch: |-
  - op: add
    path: /spec/controllerTemplate/spec/volumes/-
    value:
      name: cas-admin
  - op: add
    path: /spec/controllerTemplate/spec/volumes/-
    value:
      name: nfs-data
      nfs:
        server: ${NFS_SVR}
        path: /export/data
  - op: add
    path: /spec/controllerTemplate/spec/volumes/-
    value:
      name: nfs-homes
      nfs:
        server: ${NFS_SVR}
        path: /export/homes
  - op: add
    path: /spec/controllerTemplate/spec/containers/0/volumeMounts/-
    value:
      name: cas-admin
      mountPath: /cas/cas-admin
      readOnly: true
  - op: add
    path: /spec/controllerTemplate/spec/containers/0/volumeMounts/-
    value:
      name: nfs-data
      mountPath: /mnt/data
  - op: add
    path: /spec/controllerTemplate/spec/containers/0/volumeMounts/-
    value:
      name: nfs-homes
      mountPath: /mnt/homes
target:
  group: viya.sas.com
  kind: CASDeployment
  name: .*
  version: v1alpha1
EOF

if [[ "${V4_CFG_CAS_RAM_PER_NODE:-NA}" != "NA" ]] ; then
cat <<- EOF >> site-config/cas-transformer.yaml
# This block of code is for modifying the resource allocation for RAM. The
# default value is 2 gigabytes and the maximum value is 32 gigabytes. The
# AMOUNT-OF-RAM should be a numeric value followed by the units, such as 3Gi
# for 3 gigabytes. In Kubernetes, the units for gigabytes is Gi.
# Modify memory usage
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: cas-modify-memory
patch: |-
   - op: replace
     path: /spec/controllerTemplate/spec/containers/0/resources/requests/memory
     value:
       ${V4_CFG_CAS_RAM_PER_NODE}
   - op: add
     path: /spec/controllerTemplate/spec/containers/0/resources/limits
     value:
       memory: ${V4_CFG_CAS_RAM_PER_NODE}
   - op: add
     path: /spec/controllerTemplate/spec/containers/1/resources/requests
     value:
       memory: 500Mi
   - op: add
     path: /spec/controllerTemplate/spec/containers/1/resources/limits
     value:
       memory: 500Mi
target:
  group: viya.sas.com
  kind: CASDeployment
  name: .*
  version: v1alpha1
EOF
fi

if [[ "${V4_CFG_CAS_CORES_PER_NODE:-NA}" != "NA" ]] ; then
cat <<- EOF >> site-config/cas-transformer.yaml
# This block of code is for modifying the resource allocation for CPUs. The
# default value is .25 cores and the maximum value is 8 cores. The
# NUMBER-OF-CORES should either a whole number, representing that number of
# cores, or a number followed by m, indicating that number of milli-cores. So 8
# would mean allocating 8 cores, and 5m would mean allocating 500 milli-cores,
# or .5 cores.
# Modify CPU usage
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: cas-modify-cpu
patch: |-
   - op: replace
     path: /spec/controllerTemplate/spec/containers/0/resources/requests/cpu
     value:
       ${V4_CFG_CAS_CORES_PER_NODE}
   - op: add
     path: /spec/controllerTemplate/spec/containers/0/resources/limits/cpu
     value:
       ${V4_CFG_CAS_CORES_PER_NODE}
   - op: add
     path: /spec/controllerTemplate/spec/containers/1/resources/requests
     value:
       cpu: 500m
   - op: add
     path: /spec/controllerTemplate/spec/containers/1/resources/limits
     value:
       cpu: 500m
target:
  group: viya.sas.com
  kind: CASDeployment
  name: .*
  version: v1alpha1
EOF
fi

if [[ "${V4_CFG_CAS_WORKER_QTY:-0}" != "0" ]] ; then
cat <<- EOF >> site-config/cas-transformer.yaml
# This block of code is for specifying the number of workers in an MPP
# deployment. Do not use this block for SMP deployments. The default value is 2
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: cas-add-workers
patch: |-
   - op: replace
     path: /spec/workers
     value:
       ${V4_CFG_CAS_WORKER_QTY}
target:
  group: viya.sas.com
  kind: CASDeployment
  name: .*
  version: v1alpha1
EOF
fi

if [[ "${V4_CFG_CONFIGURE_SSSD:-false}" = "true" ]] ; then 

cat <<- EOF >> site-config/cas-transformer.yaml
# SSSD config map
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: sssd-apply-all
patch: |-
  - op: add
    path: /spec/controllerTemplate/spec/volumes/-
    value:
      name: sssd-config
      configMap:
        name: sas-sssd-config
        defaultMode: 420
        items:
        - key: SSSD_CONF
          mode: 384
          path: sssd.conf

  - op: add
    path: /spec/controllerTemplate/spec/containers/0/volumeMounts/-
    value:
      name: sssd-config
      mountPath: /etc/sssd
target:
  group: viya.sas.com
  kind: CASDeployment
  name: .*
  version: v1alpha1
EOF
fi

fi # if [ ! -f config/cas-transformer.yaml ]

if [ ! -f site-config/stateful-affinity.yaml ] ; then
cat <<- EOF >> site-config/stateful-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stateful-affinity
  labels:
    workload.sas.com/class: stateful
spec:
  template:
    metadata:
      labels:
        workload.sas.com/class: stateful
    spec:
      tolerations:
        - key: "workload.sas.com/class"
          operator: "Equal"
          value: "stateful"
          effect: "NoSchedule"
        - key: "workload.sas.com/class"
          operator: "Equal"
          value: "stateless"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io"
          operator: "Equal"
          value: "master"
          effect: "NoSchedule"
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: In
                values:
                - stateful
          - weight: 50
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: NotIn
                values:
                - compute
                - cas
                - stateless
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.azure.com/mode
                operator: NotIn
                values:
                - system
EOF
fi

if [ ! -f site-config/stateless-affinity.yaml ] ; then
cat <<- EOF >> site-config/stateless-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stateless-affinity
  labels:
    workload.sas.com/class: stateless
spec:
  template:
    metadata:
      labels:
        workload.sas.com/class: stateless
    spec:
      tolerations:
        - key: "workload.sas.com/class"
          operator: "Equal"
          value: "stateful"
          effect: "NoSchedule"
        - key: "workload.sas.com/class"
          operator: "Equal"
          value: "stateless"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io"
          operator: "Equal"
          value: "master"
          effect: "NoSchedule"
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: In
                values:
                - stateless
          - weight: 50
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: NotIn
                values:
                - compute
                - cas
                - stateful
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.azure.com/mode
                operator: NotIn
                values:
                - system
EOF
fi

if [ ! -f site-config/compute-affinity.yaml ] ; then
cat <<- EOF >> site-config/compute-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compute-affinity
  labels:
    workload.sas.com/class: compute
spec:
  template:
    metadata:
      labels:
        workload.sas.com/class: compute
  template:
    spec:
      tolerations:
        - key: "workload.sas.com/class"
          operator: "Equal"
          value: "compute"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io"
          operator: "Equal"
          value: "master"
          effect: "NoSchedule"
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: In
                values:
                - compute
          - weight: 50
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: NotIn
                values:
                - cas
                - stateless
                - stateful
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.azure.com/mode
                operator: NotIn
                values:
                - system
EOF
fi

if [ ! -f site-config/compute-podtemplate-affinity.yaml ] ; then
cat <<- EOF >> site-config/compute-podtemplate-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compute-podtemplate-affinity
template:
  metadata:
    labels:
      workload.sas.com/class: compute
  spec:
    tolerations:
      - key: workload.sas.com/class
        operator: Equal
        value: compute
        effect: NoSchedule
      - key: "node-role.kubernetes.io"
        operator: "Equal"
        value: "master"
        effect: "NoSchedule"
    affinity:
      nodeAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
            - key: workload.sas.com/class
              operator: In
              values:
              - compute
        - weight: 50
          preference:
            matchExpressions:
            - key: workload.sas.com/class
              operator: NotIn
              values:
              - cas
              - stateless
              - stateful
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: kubernetes.azure.com/mode
              operator: NotIn
              values:
              - system
EOF
fi

if [ ! -f site-config/cas-affinity.yaml ] ; then
cat <<- EOF >> site-config/cas-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cas-affinity
  labels:
    workload.sas.com/class: cas
spec:
  template:
    metadata:
      labels:
        workload.sas.com/class: cas
  controllerTemplate:
    spec:
      tolerations:
      - key: "workload.sas.com/class"
        operator: "Equal"
        value: "cas"
        effect: "NoSchedule"
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: In
                values:
                - cas
          - weight: 1
            preference:
              matchExpressions:
              - key: workload.sas.com/class
                operator: NotIn
                values:
                - compute
                - stateless
                - stateful
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.azure.com/mode
                operator: NotIn
                values:
                - system
EOF
fi

kustomize build >base.yaml

}
