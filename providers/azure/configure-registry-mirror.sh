configure-registry-mirror() {

   if [[ "${REGISTRY_MIRROR_HOSTNAME}" != "" ]] ; then
      cp bundles/default/examples/mirror/*.yaml ./
      sed ${SED_IN_PLACE} -e "s/MIRROR_HOST/${REGISTRY_MIRROR_HOSTNAME}/g" mirror.yaml

      export MIRROR_TRANSFORMER="- mirror.yaml"
      export MIRROR_CONFIG_MAP_GENERATOR=$'- name: ccp-image-location\n  behavior: merge\n  literals:\n  - CCP_IMAGE_PATH=${REGISTRY_MIRROR_HOSTNAME}'
   fi
}
