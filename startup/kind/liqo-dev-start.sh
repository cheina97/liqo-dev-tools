#!/usr/bin/env bash

FILEPATH=$(realpath "$0")
DIRPATH=$(dirname "$FILEPATH")
export DIRPATH
# shellcheck source=./utils/kind.sh
source "$DIRPATH/../../utils/kind.sh"
# shellcheck source=./utils/generic.sh
source "$DIRPATH/../../utils/generic.sh"

if [ $# -ne 3 ] || { [ "$2" != "true" ] && [ "$2" != "false" ]; } || { [ "$3" != "cilium" ] && [ "$3" != "calico" ] && [ "$3" != "kind" ] && [ "$3" != "flannel" ] ; }; then
    echo "Error: wrong parameters"
    echo "Usage: liqo-dev-start <CLUSTERS_NUMBER> <ENABLE_AUTOPEERING true|false> <CNI calico|cilium|kind>"
    exit 1
fi

END=$1
ENABLE_AUTOPEERING=$2
CNI=$3
export SERVICE_CIDR_TMPL='10.1X1.0.0/16'
export POD_CIDR_TMPL='10.1X2.0.0/16'
CLUSTER_NAMES=()
declare -A PEERING_CMDS
for i in $(seq 1 "$END"); do
    CLUSTER_NAMES+=("cheina-cluster${i}")
done

# Delete all old clusters
doforall kind-delete-cluster "${CLUSTER_NAMES[@]}"

# create registry container unless it already exists
kind-registry

# Create clusters
doforall_asyncandwait_withargandindex kind-create-cluster "${CNI}" "${CLUSTER_NAMES[@]}"

sleep 3s

# Create kubeconfig
doforall kind-get-kubeconfig "${CLUSTER_NAMES[@]}"

# Connect the registry to the cluster network if not already connected
doforall_asyncandwait kind-connect-registry "${CLUSTER_NAMES[@]}"

# Install CNI
doforall_asyncandwait_withargandindex install_cni "${CNI}" "${CLUSTER_NAMES[@]}"

# Install loadbalancer
# doforall_asyncandwait_withindex install_loadbalancer "${CLUSTER_NAMES[@]}"

# Install metrics-server
#doforall_asyncandwait metrics-server_install_kind "${CLUSTER_NAMES[@]}"

# Install kube-prometheus
#doforall_asyncandwait prometheus_install_kind "${CLUSTER_NAMES[0]}"

# Install ArgoCD
#doforall_asyncandwait install_argocd "${CLUSTER_NAMES[@]}"

# Install liqo
doforall_asyncandwait_withindex liqoctl_install_kind "${CLUSTER_NAMES[@]}"

# Deploy Dev Version
liqo-dev-deploy

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
