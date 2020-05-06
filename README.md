# viya-deployment
This tool will automate provisioning and management of multiple Viya 4 deployments.  The intent is to support deployments to azure, gcp, aws and to pre-provisioned Kubernetes instances.  Currently only azure is supported.

The intent is also to support multiple Viya 4 deployment blueprints / reference deployments. Currently only basic is supported.

The script you're looking for is [viya-deployment](viya-deployment).

The recommended getting started path is to read this page for an overview and the walk through the [GETTING_STARTED](doc/GETTING_STARTED.md) document.

For commentary re: latest changes see the [release notes](doc/RELEASE_NOTES.md).

# Things this tool can do
- Build out infrastructure in Azure to host a viya deployment
  - networking and network security
  - managed Azure DB for postgres
  - AKS cluster & node pools (node pools are labeled for stateless / stateful / compute / cas workloads)
    - installs nginx-ingress
    - installs the nfs-client PV manager
    - can install cert-manager if TLS to be configured (needs more development and testing - do not use)
    - can build infrastructure for SMP as well as MPP CAS deployments
  - jumpbox / nfs server
    - creates an ssh key combo for each deployment
  - DNS entries in azure (if not sas.com domain and so configured)
  - manage DNS entries in names.sas.com (for *.sas.com domain)
- Deploy Viya
  - Retreive the kustomization bundle from the internal API 
  - Run the kustomize process and deploy Viya
  - Create affinity rules such that processes are targeted to appropriately labeled nodes.
  - Create pod disruption budgets for each service such that cluster maintenance will not let the last instance of a service go down during a node maintenance operation for example.
  - kustomize such that data and homes directories are mounted on cas nodes and on compute server instances
  - deploy logging and monitoring optional functionality
  - deploy MPP or SMP CAS servers
- Manage a Viya deployment
  - shutdown (currently scales down all the viya service instances and terminates CAS servers - to start up again scale to 1)
  - Scale the number of nodes in AKS node pool
  - Scale the number of instances of services up and down (note there are currently bugs - do not recommend using this yet)

# Command examples

## Build out the infrastructure in Azure
viya-deployment -p azure -g kegaha -l -b basic build

## ssh into the jumpbox server
viya-deployment -p azure -g kegaha ssh

## Deploy viya in the infrastructure built above 
viya-deployment -p azure -g kegaha deploy

(if the infrastructure hasn't been built when this command runs it will be built by this command if there are sufficient defaults configured)

## Shutdown the Viya deployment built above 
viya-deployment -p azure -g kegaha shutdown

## Shutdown the Viya deployment built above without confirmation prompt
viya-deployment -p azure -g kegaha shutdown -y

## More things to know about this tool

### Default configuration specificaion and overrides
Configuration defaults can be specified for each of the following levels:  
```
.../viya-deployment/config/defaults                   <-- For the tool
      /deployments
         /cloud provider/config/defaults              <-- for the cloud provider
            /cloud provider account/config/defaults   <-- for the could provider account
               /resource group/config/defaults        <-- for the resource group
```

Values specified more deeply in the directory tree override values specified in a higher level.  Values specified on the command line override all defaults.

### Deployment configuration persistence
Configuration data about successful builds and deployments is retained in the deployments directory.  The hierarchy of the directory structure is:
```
  viya-deployment
    /deployments
      /cloud provider
        /cloud provider account
          /resource group
            /k8s namespace
```
A deployment to azure for account MyAccount to resource group named viya-rg targeting the k8s namespace kegaha would have a deployment directory named

.../viya-deployment/deployments/azure/MyAccount/viya-rg/kegaha

the working directory for a deployment can be obtained by:

viya-deployment <options> pwd. This can be helpful when many defaults are specified for the tool or provider.

### Deployment Directories

The deployment directory is used as the working directory for all commands related to the deployment.  This directory is the location to find the following:
- kustomization.yaml file
- the kustomize manifest
- a logs directory that will contain a log file for each invocation of the tool
- a config directory described below
- any number of other working directories / files specific to the deployment

Configuration information for a deployment to azure for account MyAccount to resource group named viya-rg targeting the k8s namespace kegaha would be stored in 

.../viya-deployment/deployments/azure/MyAccount/viya-rg/kegaha/config

A config directory may consist of:
```
.../config
      /.kube          <-- will contain the kube config file for the deployment
      /.ssh           <-- SSH public, private keys and ssh config file to be used for jumpbox access
      /setenv         <-- a script that can be sourced to set the interactive environment defaults to manipulate the deployment
      /defaults       <-- a list of variables that reflects the status of the deployment
```

## Azure Basic Blueprint or reference deployment
The goal of the basic configuration is to replicate what a development envrionment or a SAS testing envrironment might look like.  The configuration has very few availability features and it is not configured for performance overall.  The target is to deliver an environment that is usable at a "reasonable" cost.

The script is driven by a combination of variables specified in .../config/defaults files as specified above and command line variables.  Not all variables are yet available for override on the command line.  More command line arguments will be supported over time.  The current focus is to spin up an envrionment that is functional so we can begin learing what obvious bugs exist and what features and functions need to be added to this tooling as well as to the product.

Executing a build command with --cloud-provider azure and --blueprint basic will create the following:
- A resource group that acts as a container for most of the deployment
- A [vnet](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) that will be used to enhance security and performance
- A [network security group](https://docs.microsoft.com/en-us/azure/virtual-network/security-overview) (nsg) that will be configured with rules specified in the file nsg-rules.txt (user can specify rules)
- Two [subnets](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) on the vnet:
  - misc subnet that will home things like an NFS/jumpbox server
  - aks subnet that will home all the kubernetes components
- An NFS / jumpbox server 
  - configures underlying [VM](https://azure.microsoft.com/en-us/services/virtual-machines/linux/) 
  - configures [Azure Managed Disk](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/managed-disks-overview) and stripes the devices during configuration
  - [public IP](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-ip-addresses-overview-arm) address on the misc subnet
  - provisioned with [cloudinit](ssh-server-cloud-init.txt)
- A [service principal](https://docs.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals) for use with the AKS deployment
- An [AKS cluster](https://docs.microsoft.com/en-us/azure/aks/intro-kubernetes) with the following [node pools](https://docs.microsoft.com/en-us/azure/aks/use-multiple-node-pools):
  - system / or default node pool (this node pool can not be deleted)
  - stateless node pool for hosting the apps and services
  - compute node pool for hosting compute server processes
  - cas node pool for hosting CAS controller, backup controller, and worker processes
- An [Azure database for PostgreSQL](https://docs.microsoft.com/en-us/azure/postgresql/overview) instance for use by the deployment
- The script does not yet provision an [Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-intro) but this is one of the next capabilities to be added.

Once the deployment completes the script configures the AKS instance with:
- [nfs-client PV provisionner](https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client)
- [nginx-ingress](https://kubernetes.github.io/ingress-nginx/deploy/)
- [cert-manager](https://cert-manager.io/docs/) (if TLS is to be provisioned - coming soon)
- until we have AAD integration deploys an openldap container configured with a handful of accounts for testing
- [ops4viya](https://gitlab.sas.com/emidev/ops4viya) logging and monitoring
- If you've put the secret required to pull from the customer portal API into ~/.sasAPIkey  and configured other related variables then the script will pull the kustomization bundle down, put needed info into the kustomization.yaml file run kustomize and deploy.

There are many obvious enhancements in the works and will be coming in short order.

Note that this process uses at least 1 feature of the features of the [aks-preview extension](https://github.com/Azure/azure-cli-extensions/tree/master/src/aks-preview)

## Next Tasks 
- Get AAD / SCIM integration automated
- Handle more command line arguments
- Understand Azure NetApp Files service
