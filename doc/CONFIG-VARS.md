# List of valid configuration variables

Supported configuration variables are listed in the table below.  Some variables can also be specified on the command line.  Values specified on the command line will override all values in configuration defaults files.


  <table border="1">
  <thead>
    <tr>
      <th>Config Variable</th>
      <th>Command line</th>
      <th>Notes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>V4_CFG_BUILD_STATUS</td>
      <td>N/A</td>
	    <td>SCRIPT USE ONLY!!<br>Do not override.  Do not specify.  This variable is used within the script to determine if maintenance is being performed on a deployment.</td>
    </tr>
    <tr>
      <td>V4_CFG_CAS_SERVER_TYPE</td>
      <td>N/A</td>
	    <td>Valid values [smp | mpp].</td>
    </tr>
    <tr>
      <td>V4_CFG_CAS_WORKER_QTY</td>
      <td>N/A</td>
	    <td>Number of workers in an mpp cas server.  Defaults to 0 / smp CAS server.</td>
    </tr>
    <tr>
      <td>V4_CFG_CAS_RAM_PER_NODE</td>
      <td>N/A</td>
	    <td>Amount of RAM to request at CAS pod creation time.  Note that the value in the deployment defaults file after Viya has been deployed will be the calculated amount of RAM actually used for the memmory request and limit values.</td>
    </tr>
    <tr>
      <td>V4_CFG_CAS_CORES_PER_NODE</td>
      <td>N/A</td>
	    <td>Number of cores to request at CAS pod creation time.</td>
    </tr>
    <tr>
      <td>V4_CFG_CLOUD_PROVIDER</td>
      <td>-p | --provider | --cloud-provider</td>
	    <td>Used to specify the target cloud provider.<br>Currently supported values: azure<br>Valid values: [aws|azure|gcp|custom]
    </tr>
    <tr>
      <td>V4_CFG_CLOUD_PROVIDER_ACCOUNT</td>
      <td>-a|--account|--cloud-provider-account</td>
	    <td>Used to specify the target cloud provider account.</td>
    </tr>
    <tr>
      <td>V4_CFG_CLOUD_PROVIDER_LOCATION</td>
      <td>N/A</td>
	    <td>Used to specify the cloud provider region or location to be used for this deployment.</td>
    </tr>
    <tr>
      <td>V4_CFG_CLOUD_PROVIDER_SP_APP_ID</td>
      <td>N/A</td>
	    <td>SCRIPT USE ONLY!!<br>Do not override.  Do not specify. The service principal used to provision AKS.</td>
    </tr>
    <tr>
      <td>V4_CFG_CONFIGURE_EMBEDDED_LDAP</td>
      <td>-l | --ldap</td>
	    <td>Install the embedded ldap container.  Will be provisioned per content of config/openldap.yaml</td>
    </tr>
    <tr>
      <td>V4_CFG_CONFIGURE_SSSD</td>
      <td>N/A</td>
	    <td>[true|false] Configure SSSD If -l or --ldap are used this will be set to "true"  Should be "true" if using LDAP</td>
    </tr>
    <tr>
      <td>V4_CFG_CONFIGURE_TLS</td>
      <td>-t | --tls</td>
	    <td>[true|false] Configure TLS - This is not yet ready for production use - use only if developing the viya-deployment script.</td>
    </tr>
    <tr>
      <td>V4_CFG_DEPLOYMENT_ADMIN_ID</td>
      <td>N/A</td>
	    <td>User name created on the jumpbox server.</td>
    </tr>
    <tr>
      <td>V4_CFG_DEPLOYMENT_BLUEPRINT</td>
      <td>-b | --blueprint</td>
	    <td>Which blueprint to use to drive infrastructure buildout.  Currently supported value is basic.</td>
    </tr>
    <tr>
      <td>V4_CFG_DNS_HOST</td>
      <td>N/A</td>
	    <td>Hostname (short value - without domain / zone). of the DNS name to be used to access the deployment</td>
    </tr>
    <tr>
      <td>V4_CFG_DNS_ZONE</td>
      <td>N/A</td>
	    <td>DNS Zone / domain to be used to access the deployment</td>
    </tr>
    <tr>
      <td>V4_CFG_INSTALL_VIYA</td>
      <td>-i|--infrastructure-only</td>
	    <td>Depricated - used to be used to drive installation when the script was less command line driven</td>
    </tr>
    <tr>
      <td>V4_CFG_JUMPBOX_SSH_KEY</td>
      <td>N/A</td>
	    <td>Derived value.  Do not edit.</td>
    </tr>
    <tr>
      <td>V4_CFG_K8S_AUTHORIZED_NETWORKS</td>
      <td>N/A</td>
	    <td>Derived value.  Created from the NSG rules and the IP address of the jumpbox.</td>
    </tr>
    <tr>
      <td>V4_CFG_VM_SKU_JUMPBOX</td>
      <td>N/A</td>
	    <td>VM SKU to be used when creating the jumpbox server.</td>
    </tr>
    <tr>
      <td>V4_CFG_VM_SKU_K8S_CAS_NP</td>
      <td>N/A</td>
	    <td>VM SKU to be used when creating the CAS node pool.</td>
    </tr>
    <tr>
      <td>V4_CFG_VM_SKU_K8S_COMPUTE_NP</td>
      <td>N/A</td>
	    <td>VM SKU to be used when creating the compute node pool.</td>
    </tr>
    <tr>
      <td>V4_CFG_VM_SKU_K8S_STATEFUL_NP</td>
      <td>N/A</td>
	    <td>VM SKU to be used when creating the node pool for stateful services.</td>
    </tr>
    <tr>
      <td>V4_CFG_VM_SKU_K8S_STATELESS_NP</td>
      <td>N/A</td>
	    <td>VM SKU to be used when creating the node pool for stateless services.</td>
    </tr>
    <tr>
      <td>V4_CFG_VM_SKU_K8S_SYSTEM_NP</td>
      <td>N/A</td>
	    <td>VM SKU to be used when creating the AKS system node pool.</td>
    </tr>
    <tr>
      <td>V4_CFG_K8S_CLUSTER_NAME</td>
      <td>N/A</td>
	    <td>Name to be used for the AKS cluster.  If not specified then defaults to "${V4_CFG_TARGET_RESOURCE_GROUP}-k8s" .</td>
    </tr>
    <tr>
      <td>V4_CFG_K8S_INGRESS_TYPE</td>
      <td>N/A</td>
	    <td>Ingress controller to be used.  [ istio | ingress ] where ingress=nginx-ingress.</td>
    </tr>
    <tr>
      <td>V4_CFG_K8S_KUBECONFIG</td>
      <td>N/A</td>
	    <td>Do Not Specify.  location of the KUBECONFIG file for this deployment.</td>
    </tr>
    <tr>
      <td>V4_CFG_K8S_TARGET_NAMESPACE</td>
      <td>-n | --k8s-namespace</td>
	    <td>K8s namespace to target for the viya deployment.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_ADMIN_LOGIN</td>
      <td>N/A</td>
	    <td>Returned by the deployment.  Login to access the postgres deployment.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_BKUP_RETENTION_DAYS</td>
      <td>N/A</td>
	    <td>Number of days to retain postgres backups.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_FQDN</td>
      <td>N/A</td>
	    <td>Returned by the deployment.  FQDN of the Azure DB for postgres instance.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_INIT_STORAGE</td>
      <td>N/A</td>
	    <td>Initial Storage allocation request.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_PASSWORD</td>
      <td>N/A</td>
	    <td>Password for postgres admin user.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_SERVER_NAME</td>
      <td>N/A</td>
	    <td>Name of postgres server.  Defaults to "${V4_CFG_TARGET_RESOURCE_GROUP}-pgsql".</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_SKU</td>
      <td>N/A</td>
	    <td>SKU to be specified at time of Azure DB for postgres creation.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_USER_NAME</td>
      <td>N/A</td>
	    <td>Postgres admin user name.</td>
    </tr>
    <tr>
      <td>V4_CFG_POSTGRES_VERSION</td>
      <td>N/A</td>
	    <td>Requested version of postgres.</td>
    </tr>
    <tr>
      <td>V4_CFG_LDAP_NS</td>
      <td>N/A</td>
	    <td>Defaults to openldap.  Set this if the namespace of the ldap server needs to be called something else.</td>
    </tr>
    <tr>
      <td>V4_CFG_SAS_ORDER_NUM</td>
      <td>-o | --order-number</td>
	    <td>SAS order number to kustomize and deploy.</td>
    </tr>
    <tr>
      <td>V4_CFG_SAS_PROFILE_ID</td>
      <td>N/A</td>
	    <td>SAS Profile user name.  This is used to obtain the kustomize manifest.</td>
    </tr>
    <tr>
      <td>V4_CFG_TARGET_RESOURCE_GROUP</td>
      <td>-g | --resource-group</td>
	    <td>Name of the resource group to target with Viya deployment.</td>
    </tr>
  </tbody>
</table> 

V4_CFG_MANAGE_DNS=true
V4_CFG_NETRC_FILE=/home/kegaha/.netrc
V4_CFG_NFS_SVR_NAME=vdmml-kegaha-jump
V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS=192.168.2.4
V4_CFG_NFS_SVR_PUBLIC_IP_ADDRESS=52.251.116.103

V4_CFG_SAS_USER_ID=kegaha
V4_CFG_TLS_CERT=/home/kegaha/.tls/viya4.myviya.com_ssl_certificate.cer
V4_CFG_TLS_KEY=/home/kegaha/.tls/_.viya4.myviya.com_private_key.key
