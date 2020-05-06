# Getting Started Guide
## General Info
The tool will typically store and attempt to kocate credentials in the deployment config directory.  This is not universally true and is probably a bug that should be reported if found to be untrue.  Most attempts to locate credentials will first search the deployment config directory and will then search the user's home directory for needed credentials.

This tool currently accesses internal URLs for deployment manifests and to register *.sas.com domain names.  Mods will be required to leverage the public URLs if ever the intent is to deliver this tool outside of SAS.

Accessing the internal URL to obtain a manifest requires an API key.  Store your API key in ~/.sasAPIkey:

	echo "<my-sas-api-key-value-goes-here>" >~/.sasAPIkey

## General pattern for invoking script
Placing the cloud provider account name in a config/defaults file is highly recommended.  Assuming that is the case generally the script will be invoked passing the cloud provider and resource group name:
```
./viya-deployment -p azure -g my-rg <command>
```

## Commands 
- build			Build out cloud infrastructure
- deploy		Deploy Viya
- ssh			Initiate an ssh connection to the jumpbox server
- pwd			Display the name of the deployment directory 
- deployment	Manage a viya deployment.  Deployment currently supports the following subcommands
  - shutdown	Stop all services (stateless, stateful, and CAS)
  - scale		Scale the instances of services.  Currently the only safe value for --replicas is 1.  This is used to start a shutdown deployment
  - nodepool-info	Print info about the nodepools
  - scale-nodepool	Change the number of nodes in a nodepool

## DNS and Host Names
Manipulating DNS information managed by names.sas.com uses curl.  A .netrc file is needed to enable this.  The following will configure the needed .netrc in your home directory:

	touch ~/.netrc
	chmod 600 ~/.netrc
	cat <<-EOF >~/.netrc
	machine names.sas.com
		login <your-SAS-ID-goes-here>
		password <your-SAS-Password-goes-here>
	EOF

If using a non-SAS domain with DNS maintained in Azure there is no need to create the .netrc file.  The .netrc file is only used for names.sas.com interactions.

	git clone https://gitlab.sas.com/kegaha/viya-deployment.git
	cd viya-deployment

All host names are driven by convention based upon four specified values:
- V4_CFG_DNS_HOST is used to specify the hostname desired to represent the K8s cluster 
- V4_CFG_DNS_ZONE is used to specify the domain to be used when registering deployment related host names
- V4_CFG_K8S_TARGET_NAMESPACE is the config variable that specifies the K8s namespace to be targeted by the deployment
- V4_CFG_TARGET_RESOURCE_GROUP is the azure resource group that is a logical container for our infastructure

if I specify the following values in a config/defaults file:
- V4_CFG_DNS_HOST="az-krg"
- V4_CFG_DNS_ZONE="perf.sas.com"
- V4_CFG_K8S_TARGET_NAMESPACE="kegaha"
- V4_CFG_TARGET_RESOURCE_GROUP="krg2"

The following hostnames will be derived:
- kegaha.az-krg.perf.sas.com will be the base hostname to access the deployment for example http://kegaha.az-krg.perf.sas.com/SASDrive is the URL for SASDrive
- krg2-kegaha-jump.perf.sas.com will be the hostname of the jumpbox server
- kibana-kegaha.az-krg.perf.sas.com is the hostname to be used to access kibana (UI for viewing deployment log data)
- grafana-kegaha.az-krg.perf.sas.com is the hostname to be used to access grafana (UI for viewing deployment metrics)

## Default Passwords
The default username and password for kibana and grafana are admin / admin

## Other needed config data
The KUBECONFIG file is stored in the deployment's config/.kube/config.  There is a script that can be included in your bash session to set KUBECONFIG and to set context to use the namespace targeted for the deployment.  

The SSH key to access the jumpbox server is located in conf/.ssh/<jumpbox-hostname>


## Specifying Configuration Default Values
The script requires a fair amount of configuration to run.  Most all of the configuration can be specified in configuration defaults files.  Information that applies to most of your deployments can be specified at the tool level.  Information that is specific to a cloud provider can be specified at the cloud provider level.  Currently only Azure is supported so placing all such global config at the tool level will work fine for now.  Overrides for each new cloud provider can be specified as new providers are supported.

Use your favorite editor to edit the default configuration:

	vi config/defaults

Some example variables that you may wish to set here bearing in mind that any of these can be overridden lower in the directory tree:

	V4_CFG_SAS_ORDER_NUM="<if you wish a default order>"
	# These 2 values will be used to download Kustomize bundles via the customer portal API
	V4_CFG_SAS_PROFILE_ID="ken.gahagan@sas.com"
	V4_CFG_SAS_USER_ID="kegaha"
	
	V4_CFG_DEPLOYMENT_ADMIN_ID="sasadm"
	V4_CFG_K8S_INGRESS_TYPE="ingress" 
	V4_CFG_K8S_TARGET_NAMESPACE="kegaha"
	
	V4_CFG_DNS_HOST="az-krg"
	V4_CFG_DNS_ZONE="perf.sas.com"

	V4_CFG_DEPLOYMENT_BLUEPRINT="basic"
	V4_CFG_CONFIGURE_EMBEDDED_LDAP="true"
	V4_CFG_CLOUD_PROVIDER="azure"  # May want this here since azure is currently the only supported provider

You may wish to put azure specific things in the azure defaluts file stored in deployments/azure/config:

	#####
	# We'll make all this arguments soon but for now - just get it working
	# These variables will drive the deployment of Viya 4 to Microsoft Azure
	# Initial Assumptions are:
	#  - Azure CLI is installed
	#  - User has executed az login and has successfully logged on
	#  - User has installed the aks-preview extension (az extension add --name aks-preview)
	#####

	V4_CFG_CLOUD_PROVIDER_ACCOUNT="RDOrgASub1"
	V4_CFG_CLOUD_PROVIDER_LOCATION="eastus2"
	V4_CFG_TARGET_RESOURCE_GROUP="krg2"

	V4_CFG_POSTGRES_PASSWORD='<MyTopSecretPassword>'
	V4_CFG_POSTGRES_USER_NAME="kegaha"
	V4_CFG_POSTGRES_SKU="MO_Gen5_8"
	V4_CFG_POSTGRES_INIT_STORAGE=10240
	V4_CFG_POSTGRES_VERSION="11"
	V4_CFG_POSTGRES_BKUP_RETENTION_DAYS=7

	V4_CFG_MANAGE_DNS="true"
	V4_CFG_CONFIGURE_SSSD="true"  # At least until we get AAD integration working and automated

I will soon create a reference of all the variables that can be specified in these config files