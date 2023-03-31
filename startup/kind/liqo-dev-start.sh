#!/usr/bin/env bash

# create registry container unless it already exists
reg_name='kind-registry'
reg_port='5001'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
    docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

reg_name_proxy_ghcr='kind-registry-proxy-ghcr'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name_proxy_ghcr}" 2>/dev/null || true)" != 'true' ]; then
    docker run \
    -d --restart=always --name "${reg_name_proxy_ghcr}" \
   -e REGISTRY_PROXY_REMOTEURL="https://ghcr.io" \
    --net=kind \
    registry:2
fi

reg_name_proxy_dh='kind-registry-proxy-dh'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name_proxy_dh}" 2>/dev/null || true)" != 'true' ]; then
    docker run \
    -d --restart=always --name "${reg_name_proxy_dh}" \
   -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
    --net=kind \
    registry:2
fi

if [ $# -ne 2 ] && { [ "$2" != "true" ] &&  [ "$2" != "false" ]; }; then
    echo "Error: wrong parameters"
    echo "Usage: mio_liqostart <CLUSTERS_NUMBER> <ENABLE_AUTOPEERING true|false>"
    exit
fi

END=$1
ENABLE_AUTOPEERING=$2

CLUSTER_NAME=()
PIDS=()

for i in $(seq 1 "$END"); do
    CLUSTER_NAME+=("cluster${i}")
done

KIND="kind"

echo -e "\nDeleting old clusters"
${KIND} delete clusters --all
echo -e "\n"

i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
#export KIND_EXPERIMENTAL_DOCKER_NETWORK=kind-liqo-${CLUSTER_NAME_ITEM}
    cat << EOF > "liqo-cluster-config-$i.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  serviceSubnet: "10.1${i}1.0.0/16"
  podSubnet: "10.1${i}2.0.0/16"
nodes:
  - role: control-plane
    image: kindest/node:v1.25.0
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["http://${reg_name_proxy_dh}:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
    endpoint = ["http://${reg_name_proxy_ghcr}:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:5000"]
EOF
    ${KIND} create cluster --name "$CLUSTER_NAME_ITEM" --config "liqo-cluster-config-${i}.yaml" --wait 2m &
    PIDS+=($!)
    ((i++))
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

function install_loadbalancer(){
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    docker_net="$1"
    index="$2"
    subIp=$(docker network inspect "${docker_net}"|jq ".[0].IPAM.Config"|jq ".[0].Subnet"|cut -d . -f 2)
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
    kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - 172.${subIp}.${index}.200-172.${subIp}.${index}.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
}

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
    --local-chart-path "$HOME/Documents/liqo/liqo/deployments/liqo" \
    --version 5e418f3e7d0990b2d727c8c35aa7d87f65c5b35e    
    #--set networking.internal=false \
    #--set networking.reflectIPs=false \
    #--set gateway.service.type=LoadBalancer \
    #--set auth.service.type=LoadBalancer \

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

PIDS=()
i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    #install_loadbalancer "kind" ${i} &
    PIDS+=($!)
    (( i++ ))
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

PIDS=()
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    if [[ "${CLUSTER_NAME_ITEM}" == *"1"* ]]; then
        prometheus_install_kind &
        PIDS+=($!)
    fi
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

PIDS=()
i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    serviceMonitorEnabled="false"
    if [[ "${CLUSTER_NAME_ITEM}" == *"1"* ]]; then
        serviceMonitorEnabled="true"
    fi
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

for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    PEERING_CMDS[${CLUSTER_NAME_ITEM}]="$(liqoctl generate peer-command --only-command)"
done

if [ "$ENABLE_AUTOPEERING" == "true" ]; then
    for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
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

i=1
for CLUSTER_NAME_ITEM in "${CLUSTER_NAME[@]}"; do
    rm liqo-cluster-config-${i}.yaml
    #    rm "$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    ((i++))
done

