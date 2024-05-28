#!/usr/bin/env bash

#export NODE_VM_IMAGE_TEMPLATE="harbor.crownlabs.polito.it/capk/ubuntu-2204-container-disk:v1.28.5"
export NODE_VM_IMAGE_TEMPLATE="harbor.crownlabs.polito.it/capk/rockylinux-9-container-disk:v1.28.5"
export CRI_PATH="/var/run/containerd/containerd.sock"

DOCKER_PROXY="${DOCKER_PROXY:-docker.io}"

# Define the retry function
waitandretry() {
  local waittime="$1"
  local retries="$2"
  local command="$3"
  local options="$-" # Get the current "set" options

  sleep "${waittime}"

  echo "Running command: ${command} (retries left: ${retries})"

  # Disable set -e
  if [[ $options == *e* ]]; then
    set +e
  fi

  # Run the command, and save the exit code
  $command
  local exit_code=$?

  # restore initial options
  if [[ $options == *e* ]]; then
    set -e
  fi

  # If the exit code is non-zero (i.e. command failed), and we have not
  # reached the maximum number of retries, run the command again
  if [[ $exit_code -ne 0 && $retries -gt 0 ]]; then
    waitandretry "$waittime" $((retries - 1)) "$command"
  else
    # Return the exit code from the command
    return $exit_code
  fi
}

function install_calico() {
    local kubeconfig=$1
    local POD_CIDR=$2
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml --kubeconfig "$kubeconfig"

    # append a slash to DOCKER_PROXY if not present
    if [[ "${DOCKER_PROXY}" != */ ]]; then
        registry="${DOCKER_PROXY}/"
    else
        registry="${DOCKER_PROXY}"
    fi

    cat <<EOF > custom-resources.yaml
# This section includes base Calico installation configuration.
# For more information, see: https://projectcalico.docs.tigera.io/master/reference/installation/api#operator.tigera.io/v1.Installation
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  registry: $registry
  # Configures Calico networking.
  calicoNetwork:
    # Note: The ipPools section cannot be modified post-install.
    ipPools:
    - blockSize: 26
      cidr: $POD_CIDR
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
    nodeAddressAutodetectionV4:
      skipInterface: liqo.*

---

# This section configures the Calico API server.
# For more information, see: https://projectcalico.docs.tigera.io/master/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
    kubectl apply -f custom-resources.yaml --kubeconfig "$kubeconfig"
}

function wait_calico() {
    local kubeconfig=$1
    if ! waitandretry 5s 12 "kubectl wait --for condition=Ready=true -n calico-system pod --all --kubeconfig $kubeconfig --timeout=-1s"
    then
      echo "Failed to wait for calico pods to be ready"
      exit 1
    fi
    # set felix to use different port for VXLAN
    if ! waitandretry 5s 12 "kubectl patch felixconfiguration default --type=merge -p {\"spec\":{\"vxlanPort\":6789}} --kubeconfig $kubeconfig";
    then
      echo "Failed to patch felixconfiguration"
      exit 1
    fi
}

function install_cilium() {
    local kubeconfig=$1
    local POD_CIDR=$2

    cat <<EOF > cilium-values.yaml
ipam:
  operator:
    clusterPoolIPv4PodCIDRList: ${POD_CIDR}

affinity:
  nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: liqo.io/type
            operator: DoesNotExist

EOF

    KUBECONFIG="$kubeconfig" cilium install --values "cilium-values.yaml"
    rm cilium-values.yaml
}

function wait_cilium() {
    local kubeconfig=$1
    KUBECONFIG="$kubeconfig" cilium status --wait
}

function install_flannel() {
    local kubeconfig=$1
    local POD_CIDR=$2
    kubectl create ns kube-flannel --kubeconfig "$kubeconfig"
    kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged --kubeconfig "$kubeconfig"
    helm repo add flannel https://flannel-io.github.io/flannel/
    helm install flannel --set podCidr="${POD_CIDR}" --namespace kube-flannel flannel/flannel --kubeconfig "$kubeconfig"
}

function wait_flannel() {
    local kubeconfig=$1
    if ! waitandretry 5s 12 "kubectl wait --for condition=Ready=true -n kube-flannel pod --all --timeout=-1s --kubeconfig $kubeconfig";
    then
      echo "Failed to wait for flannel pods to be ready"
      exit 1
    fi
}

function installcni() {
    kubeconfig=$1
    cni=$2
    podcidr=$3

    case "${cni}" in
        "calico")
            install_calico "${kubeconfig}" "${podcidr}"
            wait_calico "${kubeconfig}"
            ;;
        "cilium")
            install_cilium "${kubeconfig}" "${podcidr}"
            wait_cilium "${kubeconfig}"
            ;;
        "flannel")
            install_flannel "${kubeconfig}" "${podcidr}"
            wait_flannel "${kubeconfig}"
            ;;
    esac
}

function createcluster () {
    index=$1
    cni=$2
    podcidrtype=$3

    name="cluster-${index}-${cni}-${podcidrtype}-rocky"

    if kubectl get "clusters.cluster.x-k8s.io/${name}" -n liqo-team &> /dev/null; then
        echo "Cluster ${name} already exists"
        clusterctl get kubeconfig -n liqo-team "${name}" > "${HOME}/${name}"
        return
    fi

    podcidr=""
    if [ "${podcidrtype}" == "overlapped" ]; then
        podcidr="10.80.0.0/16"
    else
        podcidr="10.8${index}.0.0/16"
    fi
    export POD_CIDR="${podcidr}"

    clusterctl generate cluster "${name}" \
        --kubernetes-version v1.28.5 \
        --control-plane-machine-count=1 \
        --worker-machine-count=2 \
        --from "${PWD}/cluster-template-liqotest.yaml" \
        --target-namespace liqo-team | kubectl apply -f -
    
    echo "Waiting for cluster ${name} to be ready"
    kubectl wait --for condition=Ready=true -n liqo-team "clusters.cluster.x-k8s.io/${name}" --timeout=-1s

    echo "Getting kubeconfig for cluster ${name}"
    clusterctl get kubeconfig -n liqo-team "${name}" > "${HOME}/${name}"

    echo "Installing CNI ${cni} on cluster ${name}"
    installcni "${HOME}/${name}" "${cni}" "${POD_CIDR}"

    echo "Installing local-path-provisioner on cluster ${name}"
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml --kubeconfig "${HOME}/${name}"
    kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --kubeconfig "${HOME}/${name}"

    echo "Installing metrics-server on cluster ${name}"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.6.4/components.yaml --kubeconfig "${HOME}/${name}"
    kubectl -n kube-system patch deployment metrics-server --type json --patch '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' --kubeconfig "${HOME}/${name}"

    echo "Installing kyverno on cluster ${name}"
    helm install kyverno kyverno/kyverno -n kyverno --create-namespace --kubeconfig "${HOME}/${name}"

    echo "Cluster ${name} ready"
}

function liqoinstall (){
    index=$1
    cni=$2
    podcidrtype=$3

    podcidr=""
    if [ "${podcidrtype}" == "overlapped" ]; then
        podcidr="10.80.0.0/16"
    else
        podcidr="10.8${index}.0.0/16"
    fi
    export POD_CIDR="${podcidr}"

    name="cluster-${index}-${cni}-${podcidrtype}-rocky"
    kubeconfig="${HOME}/${name}"

    #Check if liqo is installed with helm and if it is, skip the installation
    if helm status --kubeconfig "${kubeconfig}" -n liqo liqo &> /dev/null; then
        echo "Cluster ${name} liqo already installed"
        return
    fi

    #cd liqo
    #git checkout network-internal
    #version=$(git rev-parse HEAD)
    #cd -

    version=5a890c9231fcea3130c41d6c42bf84389d3ade82

    echo "Installing Liqo on cluster ${name}"
    KUBECONFIG="$kubeconfig" liqoctl install kubeadm \
        --cluster-name "${name}" \
        --cluster-labels="cl.liqo.io/name=${name},cl.liqo.io/kubeconfig=${name}" \
        --service-type NodePort \
        --set peering.networking.gateway.server.service.type=NodePort \
        --local-chart-path "$HOME/Documents/clusterapi/liqo/deployments/liqo" \
        --version "${version}"
}

cnis=(
    "cilium"
    "calico"
    "flannel"
)

podcidrtypes=(
    overlapped
    nonoverlapped
)

for podcidrtype in "${podcidrtypes[@]}"; do
    for cni in "${cnis[@]}"; do
        for i in {1..3}; do
            createcluster "${i}" "${cni}" "${podcidrtype}"
            liqoinstall "${i}" "${cni}" "${podcidrtype}"
        done
    done
done


