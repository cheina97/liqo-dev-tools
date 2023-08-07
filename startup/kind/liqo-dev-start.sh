#!/usr/bin/env bash

FILEPATH=$(realpath "$0")
DIRPATH=$(dirname "$FILEPATH")
export DIRPATH
# shellcheck source=./utils/kind.sh
source "$DIRPATH/../../utils/kind.sh"
# shellcheck source=./utils/generic.sh
source "$DIRPATH/../../utils/generic.sh"

function help() {
  echo "Usage: "
  echo "  liqo-dev-start [-h] [-n] [-b] [-c cni] [-p]"
  echo "Flags:"
  echo "  -h  - help"
  echo "  -n  - number of clusters"
  echo "  -b  - build"
  echo "  -c  - cni (values: kind,calico,cilium,flannel)"
  echo "  -p  - enable autopeering"
}

# Parse flags

END="2"
ENABLE_AUTOPEERING="false"
CNI="kind"
BUILD="false"

while getopts 'n:bpc:h' flag; do
  case "$flag" in
  n)
    END="$OPTARG"
    echo "Number of clusters: ${END}"
    ;;
  p)
    ENABLE_AUTOPEERING=true
    echo "Enable autopeering"
    ;;
  b)
    BUILD="true"
    echo "Build: ${BUILD}"
    ;;
  c)
    CNI="$OPTARG"
    echo "CNI: ${OPTARG}"
    ;;
  h) 
    help
    exit 0
    ;;
  *)
    help
    exit 1
    ;;
  esac
done

export SERVICE_CIDR_TMPL='10.1X1.0.0/16'
export POD_CIDR_TMPL='10.1X2.0.0/16'
CLUSTER_NAMES=()
declare -A PEERING_CMDS
for i in $(seq 1 "$END"); do
  CLUSTER_NAMES+=("cheina-cluster${i}")
done

noti -k -t "Liqo Start :rocket:" -m "Cheina started ${END} clusters"

# Delete all old clusters
doforall kind-delete-cluster "${CLUSTER_NAMES[@]}"

# create registry container unless it already exists
kind-registry

# Create clusters
doforall_asyncandwait_withargandindex kind-create-cluster "${CNI}" "${CLUSTER_NAMES[@]}"
#doforall_withargandindex kind-create-cluster "${CNI}" "${CLUSTER_NAMES[@]}"

sleep 3s

# Create kubeconfig
doforall kind-get-kubeconfig "${CLUSTER_NAMES[@]}"

# Connect the registry to the cluster network if not already connected
doforall_asyncandwait kind-connect-registry "${CLUSTER_NAMES[@]}"

# Install CNI
doforall_asyncandwait_withargandindex install_cni "${CNI}" "${CLUSTER_NAMES[@]}"

# Install loadbalancer
#doforall_asyncandwait_withindex install_loadbalancer "${CLUSTER_NAMES[@]}"

# Install metrics-server
#doforall_asyncandwait metrics-server_install_kind "${CLUSTER_NAMES[@]}"

# Install kube-prometheus
#doforall_asyncandwait prometheus_install_kind "${CLUSTER_NAMES[0]}"

# Install ArgoCD
#doforall_asyncandwait install_argocd "${CLUSTER_NAMES[@]}"

# Init Network Playground
#doforall liqo-dev-networkplayground "${CLUSTER_NAMES[@]}"

#exit 0

# Install liqo
doforall_asyncandwait_withindex liqoctl_install_kind "${CLUSTER_NAMES[@]}"

noti -k -t "Liqo Start :rocket:" -m "Cheina clusters ready :white_check_mark:"

if [ "${BUILD}" == "true" ]; then
  liqo-dev-deploy
fi

for CLUSTER_NAME_ITEM in "${CLUSTER_NAMES[@]}"; do
  export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
  PEERING_CMDS[${CLUSTER_NAME_ITEM}]="$(liqoctl generate peer-command --only-command)"
done

if [ "$ENABLE_AUTOPEERING" == "true" ]; then
  for CLUSTER_NAME_ITEM in "${CLUSTER_NAMES[@]}"; do
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    for PEERING_CMD_NAME in "${!PEERING_CMDS[@]}"; do
      if [ "${PEERING_CMD_NAME}" != "${CLUSTER_NAME_ITEM}" ]; then
        echo "Peering ${CLUSTER_NAME_ITEM} with ${PEERING_CMD_NAME}"
        echo "${PEERING_CMDS["${PEERING_CMD_NAME}"]}"
        ${PEERING_CMDS[${PEERING_CMD_NAME}]}
      fi
    done
  done
fi
