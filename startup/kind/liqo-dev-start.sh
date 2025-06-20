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
  echo "  liqo-dev-start [-h] [-n] [-b] [-c cni] [-p] [-v version]"
  echo "Flags:"
  echo "  -h  - help"
  echo "  -n  - number of clusters"
  echo "  -b  - build"
  echo "  -c  - cni (values: kind,calico,cilium,flannel)"
  echo "  -p  - enable autopeering"
  echo "  -v  - liqo version"
}

# Parse flags

END="2"
CNI="kind"
BUILD="false"

while getopts 'n:bpc:hv:' flag; do
  case "$flag" in
  n)
    END="$OPTARG"
    echo "Number of clusters: ${END}"
    ;;
  b)
    BUILD="true"
    echo "Build: ${BUILD}"
    ;;
  c)
    CNI="$OPTARG"
    echo "CNI: ${OPTARG}"
    ;;
  v)
    LIQO_VERSION="$OPTARG"
    echo "LIQO Version: ${LIQO_VERSION}"
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

if [ -z "${LIQO_VERSION}" ]; then
  echo "LIQO Version is not set. Exiting."
  exit 1
fi

export SERVICE_CIDR_TMPL='10.1X1.0.0/16'
export POD_CIDR_TMPL='10.1X2.0.0/16'
CLUSTER_NAMES=()
for i in $(seq 1 "$END"); do
  CLUSTER_NAMES+=("cheina-cluster${i}")
done

# Delete all old clusters
doforall kind-delete-cluster "${CLUSTER_NAMES[@]}"

# create registry container unless it already exists
kind-registry

# Rebuild coredns image and push it to the registry
#corednsmcs_build

# Create clusters
doforall_asyncandwait_withargandindex kind-create-cluster "${CNI}" "${CLUSTER_NAMES[@]}"
# doforall_withargandindex kind-create-cluster "${CNI}" "${CLUSTER_NAMES[@]}"

# Create kubeconfig
doforall kind-get-kubeconfig "${CLUSTER_NAMES[@]}"

# Connect the registry to the cluster network if not already connected
doforall_asyncandwait kind-connect-registry "${CLUSTER_NAMES[@]}"

# Install CNI
doforall_asyncandwait_withargandindex install_cni "${CNI}" "${CLUSTER_NAMES[@]}"

# Install loadbalancer
# DEPRECATED: now use sigs.k8s.io/cloud-provider-kind
#doforall_asyncandwait_withargandindex install_loadbalancer "${CNI}" "${CLUSTER_NAMES[@]}"

# Install ingress
# doforall_asyncandwait install_ingress "${CLUSTER_NAMES[@]}"

# Install metrics-server
# doforall_asyncandwait metrics-server_install_kind "${CLUSTER_NAMES[@]}"

# Install kube-prometheus
# doforall_asyncandwait prometheus_install_kind "${CLUSTER_NAMES[0]}"

# Install ArgoCD
# doforall_asyncandwait install_argocd "${CLUSTER_NAMES[@]}"

# Install KubeVirt
# doforall_asyncandwait install_kubevirt "${CLUSTER_NAMES[@]}"

# Install Kyverno
doforall_asyncandwait kyverno_install_kind "${CLUSTER_NAMES[@]}"

# Init Network Playground
# doforall liqo-dev-networkplayground "${CLUSTER_NAMES[@]}"

# Install liqo
doforall_asyncandwait_withargandindex liqoctl_install_kind "${LIQO_VERSION}" "${CLUSTER_NAMES[@]}"

# Install mcs CRDs
#doforall_asyncandwait mcsapi_install_kind "${CLUSTER_NAMES[@]}"

# Setup coredns multicluster
#doforall_asyncandwait corednsmcs_setup_kind "${CLUSTER_NAMES[@]}"

if [ "${BUILD}" == "true" ]; then
  liqo-dev-deploy
fi
