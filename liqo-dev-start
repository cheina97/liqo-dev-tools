#!/usr/bin/env bash

# create registry container unless it already exists
reg_name='kind-registry'
reg_port='5001'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
    docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

reg_name_proxy='kind-registry-proxy'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name_proxy}" 2>/dev/null || true)" != 'true' ]; then
    docker run \
    -d --restart=always --name "${reg_name_proxy}" \
    -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
    --net=kind \
    registry:2
fi


function setup_arch_and_os(){
    ARCH=$(uname -m)
    case $ARCH in
        armv5*) ARCH="armv5";;
        armv6*) ARCH="armv6";;
        armv7*) ARCH="arm";;
        arm64*) ARCH="arm64";;
        aarch64) ARCH="arm64";;
        x86) ARCH="386";;
        x86_64) ARCH="amd64";;
        i686) ARCH="386";;
        i386) ARCH="386";;
        *) echo "Error architecture '${ARCH}' unknown"; exit 1 ;;
    esac
    
    OS=$(uname |tr '[:upper:]' '[:lower:]')
    case "$OS" in
        # Minimalist GNU for Windows
        "mingw"*) OS='windows'; return ;;
    esac
    
    # list is available for kind at https://github.com/kubernetes-sigs/kind/releases
    # kubectl supported architecture list is a superset of the Kind one. No need to further compatibility check.
    local supported="darwin-amd64\ndarwin-arm64\nlinux-amd64\nlinux-arm64\nlinux-ppc64le\nwindows-amd64"
    if ! echo "${supported}" | grep -q "${OS}-${ARCH}"; then
        echo "Error: No version of kind for '${OS}-${ARCH}'"
        return 1
    fi
    
}

if [ $# -ne 2 ] && { [ "$2" != "true" ] &&  [ "$2" != "false" ]; }; then
    echo "Error: wrong parameters"
    echo "Usage: mio_liqostart <CLUSTERS_NUMBER> <ENABLE_AUTOPEERING true|false>"
    exit
fi

setup_arch_and_os
END=$1
ENABLE_AUTOPEERING=$2

CLUSTER_NAME=()
PIDS=()

for i in $(seq 1 "$END"); do
    CLUSTER_NAME+=("cluster${i}")
done

TMPDIR=$(mktemp -d -t liqo-install.XXXXXXXXXX)
BINDIR="${TMPDIR}/bin"
mkdir -p "${BINDIR}"

if ! command -v docker &> /dev/null;
then
    echo "MISSING REQUIREMENT: docker engine could not be found on your system. Please install docker engine to continue: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &> /dev/null;
then
    echo "Error: Docker is not running. Please start it to continue."
    exit 1
fi

if ! command -v kubectl &> /dev/null
then
    echo "WARNING: kubectl could not be found. Downloading and installing it locally..."
    if ! curl --fail -Lo "${BINDIR}"/kubectl "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${OS}/${ARCH}/kubectl"; then
        echo "Error: Unable to download kubectl for '${OS}-${ARCH}'"
        exit 1
    fi
    chmod +x "${BINDIR}"/kubectl
    export PATH=${PATH}:${BINDIR}
fi

#curl -Lo "${BINDIR}"/kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}
#chmod +x "${BINDIR}"/kind
#KIND="${BINDIR}/kind"
KIND="kind"

echo -e "\nDeleting old clusters"
${KIND} delete clusters --all
echo -e "\n"


i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
export KIND_EXPERIMENTAL_DOCKER_NETWORK=kind-liqo-${CLUSTER_NAME_ITEM}
    cat << EOF > "liqo-cluster-config-$i.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  serviceSubnet: "10.111.0.0/16"
  podSubnet: "10.112.0.0/16"
nodes:
  - role: control-plane
    image: kindest/node:v1.25.0
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["http://${reg_name_proxy}:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:5000"]
EOF
    ${KIND} create cluster --name "$CLUSTER_NAME_ITEM" --config "liqo-cluster-config-${i}.yaml" --wait 2m &
    PIDS+=($!)
    let i++
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    kind get kubeconfig --name "${CLUSTER_NAME_ITEM}" > "$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
done

# connect the registry to the cluster network if not already connected
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
    docker network connect "kind" "${reg_name}"
fi

for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    # Document the local registry
    # https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
done

declare -A PEERING_CMDS

function  liqoctl_install_kind() {
    serviceMonitorEnabled="$1"
    resourceSharingPercentage="$2"
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"

    liqoctl install kind --timeout 60m --cluster-name "${CLUSTER_NAME_ITEM}" \
    --cluster-labels="cl.liqo.io/name=${CLUSTER_NAME_ITEM}" \
    --set gateway.metrics.enabled=true \
    --set gateway.metrics.serviceMonitor.enabled="${serviceMonitorEnabled}" \
    --set controllerManager.config.resourceSharingPercentage="${resourceSharingPercentage}" \
    --disable-telemetry \
    --local-chart-path $HOME/Documents/liqo/liqo/deployments/liqo \
    --version 31ba4ee0ba68d0a5ba26929a6b9a8868ba1f0585

    #liqoctl install kind --timeout 60m --version 9f345fdfa30653103386f885b9bcf474ca4ef648 --cluster-name "$CLUSTER_NAME_ITEM" \
    #--local-chart-path $HOME/Documents/liqo/liqo/deployments/liqo \
    #--set gateway.metrics.enabled=true \
    #--set gateway.metrics.serviceMonitor.enabled="${serviceMonitorEnabled}" \
    #--disable-telemetry
}

function  metrics-server_install_kind() {
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml    
    kubectl -n kube-system patch deployment metrics-server --type json --patch '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
}

function  prometheus_install_kind() {
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    kubectl apply --server-side -f "$HOME/Documents/Kubernetes/kube-prometheus/manifests/setup"
    until kubectl get servicemonitors --all-namespaces
    do date; sleep 1; echo ""
    done
    kubectl apply -f "$HOME/Documents/Kubernetes/kube-prometheus/manifests/"
    kubectl create clusterrolebinding --clusterrole cluster-admin --serviceaccount monitoring:prometheus-k8s god
}

#PIDS=()
#for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
#    if [[ "${CLUSTER_NAME_ITEM}" == *"1"* ]]; then
#        prometheus_install_kind &
#        PIDS+=($!)
#    fi
#done

#for PID in "${PIDS[@]}"; do
#    wait "$PID"
#done

PIDS=()
i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    serviceMonitorEnabled="false"
    #if [[ "${CLUSTER_NAME_ITEM}" == *"1"* ]]; then
    #    serviceMonitorEnabled="true"
    #fi
    liqoctl_install_kind "${serviceMonitorEnabled}" "${i}0"  &
    PIDS+=($!)
    (( i++ )) || true
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

PIDS=()
i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    metrics-server_install_kind  &
    PIDS+=($!)
    (( i++ )) || true
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

#"$HOME"/Documents/liqo/scripts/dev-liqonet.sh

for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    PEERING_CMDS["${CLUSTER_NAME_ITEM}"]="$(liqoctl generate peer-command --only-command)"
done

if [ "$ENABLE_AUTOPEERING" == "true" ]; then
    for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
        export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
        for PEERING_CMD_NAME in "${!PEERING_CMDS[@]}"; do
            if [ "${PEERING_CMD_NAME}" != "${CLUSTER_NAME_ITEM}" ]; then
                echo "Peering ${CLUSTER_NAME_ITEM} with ${PEERING_CMD_NAME}"
                echo "${PEERING_CMDS["${PEERING_CMD_NAME}"]}"
                ${PEERING_CMDS["${PEERING_CMD_NAME}"]}
            fi
        done
    done
fi

i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    rm liqo-cluster-config-${i}.yaml
    #    rm "$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    let i++
done

