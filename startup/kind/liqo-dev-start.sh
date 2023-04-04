#!/usr/bin/env bash

# shellcheck source=/dev/null
FILEPATH=$(realpath "$0")
DIRPATH=$(dirname "$FILEPATH")
source "$DIRPATH/../../utils/kind.sh"
source "$DIRPATH/../../utils/generic.sh"

if [ $# -ne 3 ] || { [ "$2" != "true" ] && [ "$2" != "false" ]; } || { [ "$3" != "cilium" ] && [ "$3" != "calico" ] && [ "$3" != "kind" ] ; }; then
    echo "Error: wrong parameters"
    echo "Usage: liqo-dev-start <CLUSTERS_NUMBER> <ENABLE_AUTOPEERING true|false> <CNI calico|cilium|kind>"
    exit 1
fi

END=$1
ENABLE_AUTOPEERING=$2
CNI=$3
CLUSTER_NAMES=()
PIDS=()
declare -A PEERING_CMDS
for i in $(seq 1 "$END"); do
    CLUSTER_NAMES+=("cluster${i}")
done

# create registry container unless it already exists
kind-registry

# Delete all old clusters
kind-deleteall-cluster

# Create clusters
doforall_asyncandwait_witharg kind-create-cluster "${CNI}" "${CLUSTER_NAMES[@]}"

# Connect the registry to the cluster network if not already connected
doforall_asyncandwait kind-connect-registry "${CLUSTER_NAMES[@]}"

# Install CNI
doforall_asyncandwait_witharg install_cni "${CNI}" "${CLUSTER_NAMES[@]}"

# Install loadbalancer
doforall_asyncandwait_withindex install_loadbalancer "${CLUSTER_NAMES[@]}"

# Install kube-prometheus
doforall_asyncandwait prometheus_install_kind "${CLUSTER_NAMES[0]}"

# Install metrics-server
doforall_asyncandwait metrics-server_install_kind "${CLUSTER_NAMES[@]}"

# Install liqo
doforall_asyncandwait_withindex liqoctl_install_kind "${CLUSTER_NAMES[@]}"

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
