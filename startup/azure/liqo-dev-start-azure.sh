#!/usr/bin/env bash

CREATE_CLUSTERS=true
INSTALL_KYVERNO=false
INSTALL_LIQO=true
DESTROY=false

##### Variables #####
# shellcheck source=/dev/null
# source "$HOME/.aks/config.sh"
export AKS_SUBSCRIPTION_ID="71ca9936-5f75-498c-a20a-2ad0b9429685"

# Consumer
AKS_RESOURCE_GROUP_CONS="liqo-consumer"
AKS_RESOURCE_NAME_CONS="consumer"

# Provider 1
AKS_RESOURCE_GROUP_PROV1="liqo-provider-1"
AKS_RESOURCE_NAME_PROV1="provider1"

# Provider 2
AKS_RESOURCE_GROUP_PROV2="liqo-provider-2"
AKS_RESOURCE_NAME_PROV2="provider2"

# General
NUM_NODES="2"
VM_TYPE="Standard_B2s"
K8S_VERSION="1.28.5"
NETWORK_PLUGIN="azure" # "azure", "kubenet", "none"
OS="Ubuntu" # "AzureLinux", "CBLMariner", "Mariner", "Ubuntu"
#####################


function aks_create_cluster() {
    local aks_resource_group=$1
    local aks_resource_name=$2
    local num_nodes=$3
    local vm_type=$4

    args=()
    args+=("--subscription $AKS_SUBSCRIPTION_ID")
    args+=("--resource-group $aks_resource_group")
    args+=("--name $aks_resource_name")
    args+=("--node-count $num_nodes")
    args+=("--node-vm-size $vm_type")
    args+=("--nodepool-name $aks_resource_name")
    args+=("--kubernetes-version $K8S_VERSION")
    args+=("--network-plugin $NETWORK_PLUGIN")
    if [ $NETWORK_PLUGIN == "azure" ]; then
        args+=("--network-plugin-mode overlay")
    fi
    args+=("--pod-cidr 10.50.0.0/16") # only working on kubenet
    args+=("--tier free")
    args+=("--ssh-key-value=$HOME/.ssh/azure_${aks_resource_group}.pub")
    args+=("--os-sku $OS")
    # args+=("--node-resource-group $aks_resource_group")
    # args+=("--enable-cluster-autoscaler false")
    # args+=("--max-count 5")
    # args+=("--min-count 1")

    ARGS="${args[*]}"
    echo "az aks create $ARGS"
    az aks create $ARGS

    if [ -f "$HOME/.aks/kubeconfig-$aks_resource_name" ]; then
        rm "$HOME/.aks/kubeconfig-$aks_resource_name"
    fi
    

    az aks get-credentials \
        --subscription $AKS_SUBSCRIPTION_ID \
        --resource-group $aks_resource_group \
        --name $aks_resource_name \
        --file "$HOME/.aks/kubeconfig-$aks_resource_name"
}

function install_kyverno() {
    local aks_resource_name="$1"

    local NAME="$aks_resource_name"
    local KUBECONFIG="$HOME/.aks/kubeconfig-$NAME"

    echo Installing Kyverno on $NAME $PROVIDER cluster

    helm install kyverno kyverno/kyverno -n kyverno --create-namespace --kubeconfig $KUBECONFIG

    echo "Kyverno installed on $NAME $PROVIDER cluster"

    return 0
}


function install_liqo() {
    local aks_resource_group=$1
    local aks_resource_name=$2
    local VERSION="$3"
    local CHART="$4"

    local NAME="$aks_resource_name"
    local KUBECONFIG="$HOME/.aks/kubeconfig-$NAME"
    if [[ "$CHART" != "" ]]; then
        arg_chart="--local-chart-path $CHART"
    fi

    echo Installing Liqo on $NAME cluster
    echo Using Liqoctl version: "$(liqoctl version --client)"
    echo Installing Liqo version: "$VERSION"

    liqoctl install aks --kubeconfig $KUBECONFIG \
        --cluster-name $NAME \
        --subscription-id $AKS_SUBSCRIPTION_ID \
        --resource-group-name $aks_resource_group \
        --resource-name $aks_resource_name \
        --version $VERSION $arg_chart \
        --cluster-labels=cl.liqo.io/kubeconfig=kubeconfig-$NAME \
        --disable-telemetry --verbose \
        --pod-cidr "10.50.0.0/16"
        # --vnet-resource-group-name "MC_liqo_consumer_germanywestcentral" \
        # --set "ipam.reservedSubnets={10.156.0.0/16}" \
    
    echo "Liqo installed on $NAME cluster"

    return 0
}

# Create AKS clusters
if [[ $CREATE_CLUSTERS == true ]]; then
    PIDS=()
    aks_create_cluster ${AKS_RESOURCE_GROUP_CONS} ${AKS_RESOURCE_NAME_CONS} ${NUM_NODES} ${VM_TYPE} &
    PIDS+=($!) 
    aks_create_cluster ${AKS_RESOURCE_GROUP_PROV1} ${AKS_RESOURCE_NAME_PROV1} ${NUM_NODES} ${VM_TYPE} &
    PIDS+=($!)
    aks_create_cluster ${AKS_RESOURCE_GROUP_PROV2} ${AKS_RESOURCE_NAME_PROV2} ${NUM_NODES} ${VM_TYPE} &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi

# Install Kyverno
if [[ $INSTALL_KYVERNO == true ]]; then
    helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
    PIDS=()
    install_kyverno $AKS_RESOURCE_NAME_CONS &
    PIDS+=($!)
    install_kyverno $AKS_RESOURCE_NAME_PROV1 &
    PIDS+=($!)
    install_kyverno $AKS_RESOURCE_NAME_PROV2 &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi


# Install Liqo
VERSION=v1.0.0-rc.1    # v0.10.3
CHART="$HOME/Documents/liqo/liqo/deployments/liqo"       # ""
if [[ $INSTALL_LIQO == true ]]; then
    PIDS=()
    install_liqo $AKS_RESOURCE_GROUP_CONS $AKS_RESOURCE_NAME_CONS $VERSION $CHART &
    PIDS+=($!)
    install_liqo $AKS_RESOURCE_GROUP_PROV1 $AKS_RESOURCE_NAME_PROV1 $VERSION $CHART &
    PIDS+=($!)
    install_liqo $AKS_RESOURCE_GROUP_PROV2 $AKS_RESOURCE_NAME_PROV2 $VERSION $CHART &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi

# Delete AKS clusters
if [[ $DESTROY == true ]]; then
    PIDS=()
    az aks delete --resource-group $AKS_RESOURCE_GROUP_CONS --name $AKS_RESOURCE_NAME_CONS --yes &
    PIDS+=($!)
    az aks delete --resource-group $AKS_RESOURCE_GROUP_PROV1 --name $AKS_RESOURCE_NAME_PROV1 --yes &
    PIDS+=($!)
    az aks delete --resource-group $AKS_RESOURCE_GROUP_PROV2 --name $AKS_RESOURCE_NAME_PROV2 --yes &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi