#!/usr/bin/env bash

reg_name='kind-registry'
reg_port='5001'

function kind-registry() {
  if [ -z "$(docker network ls | grep kind)" ]; then
    docker network create kind
  fi

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

  reg_name_proxy_quay='kind-registry-proxy-quay'
  if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name_proxy_quay}" 2>/dev/null || true)" != 'true' ]; then
    docker run \
      -d --restart=always --name "${reg_name_proxy_quay}" \
      -e REGISTRY_PROXY_REMOTEURL="https://quay.io" \
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

function kind-get-kubeconfig() {
  cluster_name="$1"
  kind get kubeconfig --name "${cluster_name}" >"$HOME/liqo-kubeconf-${cluster_name}"
}

function kind-delete-cluster() {
  cluster_name=$1
  echo "Deleting ${cluster_name}"
  kind delete clusters "${cluster_name}"
}

function kind-connect-registry() {
  cluster_name="$1"
  # Connect the registry to the cluster network if not already connected
  if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
    docker network connect "kind" "${reg_name}"
  fi

  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
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

function install_loadbalancer() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  #docker_net=kind-liqo-${cluster_name}
  docker_net="kind"
  index="$2"
  CNI=$3
  subIp=$(docker network inspect "${docker_net}" | jq ".[0].IPAM.Config" | jq ".[1].Subnet" | cut -d . -f 2)
  subIp=18

  echo "Setting LoadBalancer pool 172.${subIp}.${index}.200-172.${subIp}.${index}.250"
  if [ "${CNI}" == "cilium-no-kubeproxy" ]; then
    until kubectl get crd ciliumloadbalancerippools.cilium.io ciliuml2announcementpolicies.cilium.io 2>/dev/null; do
      sleep 1s
    done
    export subIp
    export index
    envsubst <"$DIRPATH/../../utils/cilium-lb.yaml" | kubectl apply -f -
  else
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
    until kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s 2>/dev/null; do
      sleep 1s
    done
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
  fi

}

function install_ingress() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.ingressClassResource.default=true
}

function install_argocd() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  tput setaf 5
  tput bold
  echo "Get ArgoCD initial password for ${cluster_name} width:"
  echo 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo'
  tput sgr0
}

function install_kubevirt() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"

  local KUBEVIRT_VERSION
  KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
  kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
  kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

  local CDI_VERSION
  CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"
  kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"
}

function install_cni() {
  cluster_name=$1
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  index=$2
  CNI=$3
  POD_CIDR=$(echo "$POD_CIDR_TMPL" | sed "s/X/${index}/g")
  #POD_CIDR="10.127.64.0/18"

  POD_CIDR=""
  if [[ "${index}" == "1" ]]; then
    POD_CIDR="10.101.0.0/16"
  else
    POD_CIDR="10.102.0.0/16"
  fi

  if [ "${CNI}" == cilium ] || [ "${CNI}" == "cilium-no-kubeproxy" ]; then
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/experimental/gateway.networking.k8s.io_grpcroutes.yaml
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

    if [ "${CNI}" == "cilium" ]; then
      cilium install --wait --values "$DIRPATH/../../utils/cilium-values.yaml"
    fi

    if [ "${CNI}" == "cilium-no-kubeproxy" ]; then
      APIIP=$(kubectl get po -n kube-system -o wide "kube-apiserver-${cluster_name}-control-plane" -o jsonpath='{.status.podIP}')
      cilium install --values "$DIRPATH/../../utils/cilium-values.yaml" \
        --set kubeProxyReplacement=true \
        --set k8sServiceHost="${APIIP}" \
        --set k8sServicePort="6443"
    fi

  elif [ "${CNI}" == calico ]; then
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
    export POD_CIDR
    envsubst <"$DIRPATH/../../utils/calico.yaml" | kubectl apply -f -
  elif [ "${CNI}" == flannel ]; then
    # Needs manual creation of namespace to avoid helm error
    kubectl create ns kube-flannel
    kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged
    helm repo add flannel https://flannel-io.github.io/flannel/
    helm install flannel --set podCidr="${POD_CIDR}" --namespace kube-flannel flannel/flannel
    kubectl wait --for=condition=ready pod --selector=app=flannel --timeout=90s -n kube-flannel
  fi

  echo "Waiting for nodes to be ready"
  kubectl wait --for=condition=ready node --all --timeout=90s
  echo "Nodes are ready"
}

function build_liqo() {
  local tag
  tag="${NOW}"
  local build_start_time
  build_start_time=$(date +%s)
  for component in "${OVERRIDE_COMPONENTS[@]}"; do
    liqo-dev-deploy -b -t "${tag}" -c "${component}" 1>&2
  done
  local build_end_time
  build_end_time=$(date +%s)
  local build_duration=$((build_end_time - build_start_time))
  echo "Build completed in ${build_duration} seconds"
}

function liqoctl_install_kind() {
  local cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  local index="$2"
  local current_version="$3"

  local monitorEnabled="false"
  #if [ "${index}" == "1" ]; then
  #    monitorEnabled="true"
  #fi

  flags_override=()

  if [ "${BUILD}" == "true" ]; then
    local tag
    tag="${NOW}"
    for component in "${OVERRIDE_COMPONENTS[@]}"; do
      case "${component}" in
      "controller-manager")
        flags_override+=("--set-string=controllerManager.image.name=localhost:5001/liqotech/liqo-${component}-ci")
        flags_override+=("--set-string=controllerManager.image.version=${tag}")
        ;;
      "virtual-kubelet")
        flags_override+=("--set-string=virtualKubelet.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=virtualKubelet.image.version=${tag}")
        ;;
      "metric-agent")
        flags_override+=("--set-string=metricAgent.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=metricAgent.image.version=${tag}")
        ;;
      "gateway")
        flags_override+=("--set-string=networking.gatewayTemplates.container.gateway.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=networking.gatewayTemplates.container.gateway.image.version=${tag}")
        ;;
      "gateway/wireguard")
        flags_override+=("--set-string=networking.gatewayTemplates.container.wireguard.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=networking.gatewayTemplates.container.wireguard.image.version=${tag}")
        ;;
      "gateway/geneve")
        flags_override+=("--set-string=networking.gatewayTemplates.container.geneve.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=networking.gatewayTemplates.container.geneve.image.version=${tag}")
        ;;
      "ipam")
        flags_override+=("--set-string=ipam.internal.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=ipam.internal.image.version=${tag}")
        ;;
      "fabric")
        flags_override+=("--set-string=networking.fabric.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=networking.fabric.image.version=${tag}")
        ;;
      "crd-replicator")
        flags_override+=("--set-string=crdReplicator.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=crdReplicator.image.version=${tag}")
        ;;
      "proxy")
        flags_override+=("--set-string=proxy.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=proxy.image.version=${tag}")
        ;;
      "webhook")
        flags_override+=("--set-string=webhook.image.name=localhost:5001/liqotech/${component}-ci")
        flags_override+=("--set-string=webhook.image.version=${tag}")
        ;;
      esac
    done
  fi

  # For debugging, you can inspect the array like this:
  # declare -p flags

  local install_start_time
  install_start_time=$(date +%s)

  # ✅ Use the correct expansion syntax: "${flags[@]}"
  liqoctl install kind --cluster-id "${cluster_name}" \
    --timeout "180m" \
    --enable-metrics \
    --cluster-labels="cl.liqo.io/name=${cluster_name}" \
    --local-chart-path "$HOME/Documents/liqo/liqo/deployments/liqo" \
    --version "${current_version}" \
    --set networking.fabric.config.fullMasquerade=true \
    --set networking.fabric.config.gatewayMasqueradeBypass=true \
    --set metrics.enabled=true \
    --set "metrics.prometheusOperator.enabled=${monitorEnabled}" \
    --set ipam.internal.graphviz=false \
    --set "ipam.reservedSubnets={172.17.0.0/16}" \
    --set "networking.gatewayTemplates.wireguard.implementation=kernel" \
    "${flags_override[@]}"

  local install_end_time
  install_end_time=$(date +%s)
  local install_duration=$((install_end_time - install_start_time))
  echo "Liqoctl install completed in ${install_duration} seconds"

  #--set networking.gatewayTemplates.wireguard.implementation=userspace \

  #--set controllerManager.config.enableNodeFailureController=true \
  #--set gateway.service.type=LoadBalancer \
  #--set auth.service.type=LoadBalancer

  #--set networking.internal=false \
  #--set networking.reflectIPs=false \

  #liqoctl install kind --timeout 60m --version 9f345fdfa30653103386f885b9bcf474ca4ef648 --cluster-name "$cluster_name" \
  #--local-chart-path $HOME/Documents/liqo/liqo/deployments/liqo \
  #--set gateway.metrics.enabled=true \
  #--set gateway.metrics.serviceMonitor.enabled="${serviceMonitorEnabled}" \
  #--disable-telemetry
}

function metrics-server_install_kind() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl -n kube-system patch deployment metrics-server --type json --patch '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
}

function prometheus_install_kind() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"

  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n kube-prometheus-stack --values "$DIRPATH/../../utils/kube-prometheus.yaml" --create-namespace --wait
}

function kyverno_install_kind() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  helm install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
}

function certmanager_install_kind() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
}

function mcsapi_install_kind() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/mcs-api/v0.1.0/config/crd/multicluster.x-k8s.io_serviceexports.yaml
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/mcs-api/v0.1.0/config/crd/multicluster.x-k8s.io_serviceimports.yaml
}

function corednsmcs_build() {
  coredns_image="localhost:5001/multicluster/coredns:latest"
  coredns_path="${HOME}/Documents/coredns"

  pushd "${coredns_path}" || exit

  if ! grep -q -F 'multicluster:github.com/coredns/multicluster' "plugin.cfg"; then
    sed -i -e 's/^kubernetes:kubernetes$/&\nmulticluster:github.com\/coredns\/multicluster/' "plugin.cfg"
  fi

  make
  docker build -t "${coredns_image}" .
  docker push "${coredns_image}"

  popd || exit
}

function corednsmcs_setup_kind() {
  cluster_name="$1"
  export KUBECONFIG="$HOME/liqo-kubeconf-${cluster_name}"

  COREDNS_RBAC_PATCHFILE="${DIRPATH}/../../utils/coredns-rbac.json"

  kubectl patch clusterrole system:coredns --type json --patch-file "${COREDNS_RBAC_PATCHFILE}"
  kubectl get configmap -n kube-system coredns -o yaml |
    sed -E -e 's/^(\s*)kubernetes.*cluster\.local.*$/\1multicluster clusterset.local\n&/' |
    kubectl replace -f-
  kubectl rollout restart deploy -n kube-system coredns
}

function kind-create-cluster() {
  cluster_name=$1
  #export KIND_EXPERIMENTAL_DOCKER_NETWORK=${cluster_name}
  #if [ -z "$(docker network ls | grep $KIND_EXPERIMENTAL_DOCKER_NETWORK)" ]; then
  #  echo "Creating network $KIND_EXPERIMENTAL_DOCKER_NETWORK"
  #  docker network create  --opt com.docker.network.bridge.name="$KIND_EXPERIMENTAL_DOCKER_NETWORK" "$KIND_EXPERIMENTAL_DOCKER_NETWORK"
  #fi

  index=$2
  CNI=$3
  POD_CIDR=$(echo "$POD_CIDR_TMPL" | sed "s/X/${index}/g")
  #POD_CIDR="10.127.64.0/18"
  SERVICE_CIDR=$(echo "$SERVICE_CIDR_TMPL" | sed "s/X/${index}/g")
  #SERVICE_CIDR=10.103.0.0/16

  POD_CIDR=""
  if [[ "${index}" == "1" ]]; then
    POD_CIDR="10.101.0.0/16"
  else
    POD_CIDR="10.102.0.0/16"
  fi

  DISABLEDEFAULTCNI="false"
  if [ "$CNI" != "kind" ]; then
    DISABLEDEFAULTCNI="true"
  fi

  KUBEPROXYMODE="iptables"
  if [ "$CNI" == "cilium-no-kubeproxy" ]; then
    KUBEPROXYMODE="none"
  fi

  # Adds the following to the kind config to run flannel:
  #nodes:
  #  - role: control-plane
  #    image: kindest/node:v1.30.0
  #    extraMounts:
  #      - hostPath: /opt/cni/bin
  #        containerPath: /opt/cni/bin
  #  - role: worker
  #    image: kindest/node:v1.30.0
  #    extraMounts:
  #      - hostPath: /opt/cni/bin
  #        containerPath: /opt/cni/bin
  #  - role: worker
  #    image: kindest/node:v1.30.0
  #    extraMounts:
  #      - hostPath: /opt/cni/bin
  #        containerPath: /opt/cni/bin

  # Adds the following to the kind config to disable kube-proxy:
  #kubeProxyMode: "none"

  #kubeadmConfigPatches:
  #- |
  #  kind: ClusterConfiguration
  #  dns:
  #    imageRepository: localhost:5001/multicluster
  #    imageTag: latest

  cat <<EOF >"liqo-${cluster_name}-config.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  serviceSubnet: "${SERVICE_CIDR}"
  podSubnet: "${POD_CIDR}"
  kubeProxyMode: "${KUBEPROXYMODE}"
  disableDefaultCNI: ${DISABLEDEFAULTCNI}
nodes:
  - role: control-plane
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["http://${reg_name_proxy_dh}:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
    endpoint = ["http://${reg_name_proxy_ghcr}:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
    endpoint = ["http://${reg_name_proxy_quay}:5000"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:5000"]
EOF
  kind create cluster --name "${cluster_name}" --config "liqo-${cluster_name}-config.yaml"
  rm "liqo-${cluster_name}-config.yaml"
  echo "Cluster ${cluster_name} created"
  #kubectl taint node "${cluster_name}-control-plane" node-role.kubernetes.io/control-plane- || true
}
