#!/usr/bin/env bash

reg_name='kind-registry'
reg_port='5001'

function kind-registry () {
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
}

function kind-create-cluster () {
    #export KIND_EXPERIMENTAL_DOCKER_NETWORK=kind-liqo-${cluster_name}
    cluster_name=$1
    index=$2
    CNI=$3

    DISABLEDEFAULTCNI="false"
    if [ "$CNI" != "kind" ]; then
        DISABLEDEFAULTCNI="true"
    fi

    cat << EOF > "liqo-${cluster_name}-config.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  serviceSubnet: "10.1${index}1.0.0/16"
  podSubnet: "10.1${index}2.0.0/16"
  disableDefaultCNI: ${DISABLEDEFAULTCNI}
nodes:
  - role: control-plane
    image: kindest/node:v1.25.0
  - role: worker
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
    kind create cluster --name "${cluster_name}" --config "liqo-${cluster_name}-config.yaml"
    rm "liqo-${cluster_name}-config.yaml"
    kind get kubeconfig --name "${cluster_name}" > "$HOME/liqo_kubeconf_${cluster_name}"
}

function kind-deleteall-cluster () {
    echo -e "\nDeleting old clusters"
    kind delete clusters --all
    echo -e "\n"
}

function kind-connect-registry () {
    cluster_name="$1"
    # Connect the registry to the cluster network if not already connected
    if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
        docker network connect "kind" "${reg_name}"
    fi

    export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}"
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
}

function install_loadbalancer(){
    cluster_name="$1"
    export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}"
    #docker_net=kind-liqo-${cluster_name}
    docker_net="kind"
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

function install_cni(){
    cluster_name="$1"
    export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}"

    cni="$2"
    if [ "${cni}" == cilium ]; then
        cilium install --wait
    elif [ "${cni}" == calico ]; then
        kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
        curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/custom-resources.yaml -O
        kubectl create -f custom-resources.yaml
    fi
}

function  liqoctl_install_kind() {
    cluster_name="$1"
    export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}"
    index="$2"

    serviceMonitorEnabled="false"
    #if [ "${index}" == "1" ]; then
    #    serviceMonitorEnabled="true"
    #fi

    liqoctl install kind --timeout 60m --cluster-name "${cluster_name}" \
    --cluster-labels="cl.liqo.io/name=${cluster_name}" \
    --set gateway.metrics.enabled=true \
    --set gateway.metrics.serviceMonitor.enabled="${serviceMonitorEnabled}" \
    --set controllerManager.config.resourceSharingPercentage="${index}0" \
    --disable-telemetry \
    --local-chart-path "$HOME/Documents/liqo/liqo/deployments/liqo" \
    --version 5e418f3e7d0990b2d727c8c35aa7d87f65c5b35e    
    #--set networking.internal=false \
    #--set networking.reflectIPs=false \
    #--set gateway.service.type=LoadBalancer \
    #--set auth.service.type=LoadBalancer \

    #liqoctl install kind --timeout 60m --version 9f345fdfa30653103386f885b9bcf474ca4ef648 --cluster-name "$cluster_name" \
    #--local-chart-path $HOME/Documents/liqo/liqo/deployments/liqo \
    #--set gateway.metrics.enabled=true \
    #--set gateway.metrics.serviceMonitor.enabled="${serviceMonitorEnabled}" \
    #--disable-telemetry
}

function  metrics-server_install_kind() {
    cluster_name="$1"
    export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml    
    kubectl -n kube-system patch deployment metrics-server --type json --patch '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
}

function  prometheus_install_kind() {
    cluster_name="$1"
    export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}"
    kubectl apply --server-side -f "$HOME/Documents/Kubernetes/kube-prometheus/manifests/setup"
    until kubectl get servicemonitors --all-namespaces
    do date; sleep 1; echo ""
    done
    kubectl apply -f "$HOME/Documents/Kubernetes/kube-prometheus/manifests/"
    kubectl create clusterrolebinding --clusterrole cluster-admin --serviceaccount monitoring:prometheus-k8s god
}