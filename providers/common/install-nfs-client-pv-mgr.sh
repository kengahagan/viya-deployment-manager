install-nfs-client-pv-mgr() {
	# see https://github.com/helm/charts/tree/master/stable/nfs-client-provisioner 

	if kubectl get ns nfs-client ; then
		if [[ "${FORCE_DEPLOY_K8S_PREREQS}" = "true" ]] ; then
			log-message "nfs-client namespace exists - uninstalling"
			helm uninstall nfs-client stable/nfs-client-provisioner \
				--kubeconfig="${V4_CFG_K8S_KUBECONFIG}" \
				--namespace nfs-client \
			| tee -a "${LOG_FILE}"

			kubectl delete ns nfs-client
		else
			return
		fi
	fi

	case "${V4_CFG_CLOUD_PROVIDER}" in 
		azure)
			NFS_SVR="${V4_CFG_NFS_SVR_PRIVATE_IP_ADDRESS}" 
		;;
		custom)
			NFS_SVR="${V4_CFG_NFS_SVR_NAME}"
		;;
	esac

	log-message "installing nfs-client-provisioner configured to ${NFS_SVR}"
	# do not use 		--set storageClass.defaultClass=true \ for now.
	kubectl create ns nfs-client
	helm install nfs-client stable/nfs-client-provisioner \
		--kubeconfig="${V4_CFG_K8S_KUBECONFIG}" \
		--namespace nfs-client \
		--set nfs.server="${NFS_SVR}"  \
		--set nfs.path="${V4_CFG_NFS_SVR_PATH:-/export/pvs}"  \
		--set podSecurityPolicy.enabled=true \
	| tee -a "${LOG_FILE}"
}
