# Release Notes

## 03May2020:
- deployment-directory/config has been renamed deployment-directory/site-config.  The script recognizes the old structure and will rename config -> site-config and create a link
- Now supports MPP CAS server deployment.  See [CONFIG-VARS](CONFIG-VARS.md) for relevant config information.
- Requests the amount of allocatable RAM on CAS nodes and sets requests and limits on the CAS deployment to realize guaranteed QoS
- Initial support for on-prem / custom clusters
  - Will deploy the K8s pre-reqs
  - Will deploy Viya with same config as in cloud
- get-logs is now a valid sub-command for the deployment command.  Will get all pod logs and save them to the DEPLOYMENT directory in a directory named with the datetime as the name.
- Should handle new OCI / cadence-based orders as well as legacy ship event based orders
- If MAS is detected in the order:
  - Will create an ASTORES PVC and kustomize into all the appropriate deployed services
  - Will tar up python, copy to the NFS server, untar, kustomize needed info such that the python location is recognized


