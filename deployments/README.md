# Deployments directory
The deployments directory contains configuration and logs for a given cloud provider / account / resource group / namespace combination.

- Configs are stored in a directory hierarchy that matches the deployment combination hierarchy.
- if a config directory exists in any given level it overrides the values of the parent directory or level
- the config directory located in the same directory as the viya-deployment script provides global defaults that can be overridden with more specific values with each configuration level
- place a file named defaults in the config directory of any deployment sub-directory to override the values specified at a higher level
- defaults files should contain name / value pairs specifying environment variables and their values
- values specified on the command line override values in all defaults files.


if a link named default exists in this directory then the linked directory will be used as a shortcut if no parameters are provided.  A default is not set automatically.  To specify a default deployment use the set-default deployment subcommand

if viya-deployment is invoked from a deployment directory the config values from the deployment config directory (and all parent config directories) will be picked up automatically.