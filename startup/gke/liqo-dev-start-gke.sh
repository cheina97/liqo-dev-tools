#!/usr/bin/env bash

CREATE_CLUSTERS=false
INSTALL_KYVERNO=false
INSTALL_LIQO=false
DESTROY=true

##### Variables #####
export GKE_SERVICE_ACCOUNT_PATH="$HOME/.liqo/gcp_service_account"
export GKE_PROJECT_ID="progetto-liqo-cloud"

# Consumer
GKE_CLUSTER_ID_CONS="consumer"
GKE_CLUSTER_REGION_CONS="europe-west1" #"europe-central2"
GKE_CLUSTER_ZONE_CONS="europe-west1-c" #"europe-central2-a"

# Provider 1
GKE_CLUSTER_ID_PROV1="provider1"
GKE_CLUSTER_REGION_PROV1="europe-west2"
GKE_CLUSTER_ZONE_PROV1="europe-west2-b"

# Provider 2
GKE_CLUSTER_ID_PROV2="provider2"
GKE_CLUSTER_REGION_PROV2="europe-west3"
GKE_CLUSTER_ZONE_PROV2="europe-west3-a"

# General
NUM_NODES="1"
MACHINE_TYPE="e2-standard-2" # "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4"
IMAGE_TYPE="COS_CONTAINERD" # "COS_CONTAINERD", "UBUNTU_CONTAINERD"
DISK_TYPE="pd-balanced"
DISK_SIZE="10"
DATAPLANE="v1" # "v1", "v2"
#####################


function gke_create_cluster() {
    local cluster_id=$1
    local cluster_region=$2
    local cluster_zone=$3
    local num_nodes=$4
    local machine_type=$5
    local image_type=$6
    local disk_type=$7
    local disk_size=$8

    local cluster_version=" 1.30"

    if [[ $DATAPLANE == "v2" ]]; then
        arg_dataplane="--enable-dataplane-v2"
    fi

    gcloud container --project $GKE_PROJECT_ID clusters create $cluster_id --zone $cluster_zone \
        --num-nodes $num_nodes --machine-type $machine_type --image-type $image_type --disk-type $disk_type --disk-size $disk_size \
        --cluster-version $cluster_version $arg_dataplane --no-enable-intra-node-visibility --enable-shielded-nodes --enable-ip-alias \
        --release-channel "regular" --no-enable-basic-auth --metadata disable-legacy-endpoints=true \
        --network "projects/$GKE_PROJECT_ID/global/networks/default" --subnetwork "projects/$GKE_PROJECT_ID/regions/$cluster_region/subnetworks/default" \
        --default-max-pods-per-node "110" --security-posture=standard --workload-vulnerability-scanning=disabled --no-enable-master-authorized-networks \
        --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --binauthz-evaluation-mode=DISABLED --no-enable-insecure-kubelet-readonly-port \
        --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
        --no-enable-managed-prometheus
        # --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
        # --enable-autoupgrade \
        # --enable-managed-prometheus --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM

    export KUBECONFIG="$HOME/.gke/kubeconfig-$cluster_id"
    gcloud container clusters get-credentials $cluster_id --zone $cluster_zone --project $GKE_PROJECT_ID
    unset KUBECONFIG

    return 0
}

function install_kyverno() {
    local GKE_CLUSTER_ID="$1"

    local NAME="$GKE_CLUSTER_ID"
    local KUBECONFIG="$HOME/.gke/kubeconfig-$NAME"

    echo Installing Kyverno on $NAME $PROVIDER cluster

    helm install kyverno kyverno/kyverno -n kyverno --create-namespace --kubeconfig $KUBECONFIG

    echo "Kyverno installed on $NAME $PROVIDER cluster"

    return 0
}

function install_liqo() {
    local GKE_CLUSTER_ID="$1"
    local GKE_CLUSTER_ZONE="$2"
    local VERSION="$3"
    local CHART="$4"

    local NAME="$GKE_CLUSTER_ID"
    local KUBECONFIG="$HOME/.gke/kubeconfig-$NAME"
    if [[ "$CHART" != "" ]]; then
        arg_chart="--local-chart-path $CHART"
    fi

    echo Installing Liqo on $NAME cluster
    echo Using Liqoctl version: "$(liqoctl version --client)"
    echo Installing Liqo version: "$VERSION"

    liqoctl install gke --kubeconfig $KUBECONFIG \
        --project-id $GKE_PROJECT_ID \
        --cluster-id $GKE_CLUSTER_ID \
        --zone $GKE_CLUSTER_ZONE \
        --credentials-path $GKE_SERVICE_ACCOUNT_PATH \
        --version $VERSION $arg_chart \
        --set auth.service.type=NodePort \
        --disable-telemetry --verbose
        # --set "ipam.reservedSubnets={10.156.0.0/16}" \
    
    echo "Liqo installed on $NAME cluster"

    return 0
}


# Create GKE clusters
if [[ $CREATE_CLUSTERS == true ]]; then
    PIDS=()
    gke_create_cluster ${GKE_CLUSTER_ID_CONS} ${GKE_CLUSTER_REGION_CONS} ${GKE_CLUSTER_ZONE_CONS} ${NUM_NODES} ${MACHINE_TYPE} ${IMAGE_TYPE} ${DISK_TYPE} ${DISK_SIZE} &
    PIDS+=($!) 
    gke_create_cluster ${GKE_CLUSTER_ID_PROV1} ${GKE_CLUSTER_REGION_PROV1} ${GKE_CLUSTER_ZONE_PROV1} ${NUM_NODES} ${MACHINE_TYPE} ${IMAGE_TYPE} ${DISK_TYPE} ${DISK_SIZE} &
    PIDS+=($!)
    gke_create_cluster ${GKE_CLUSTER_ID_PROV2} ${GKE_CLUSTER_REGION_PROV2} ${GKE_CLUSTER_ZONE_PROV2} ${NUM_NODES} ${MACHINE_TYPE} ${IMAGE_TYPE} ${DISK_TYPE} ${DISK_SIZE} &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi


# Install Kyverno
if [[ $INSTALL_KYVERNO == true ]]; then
    helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
    PIDS=()
    install_kyverno $GKE_CLUSTER_ID_CONS &
    PIDS+=($!)
    install_kyverno $GKE_CLUSTER_ID_PROV1 &
    PIDS+=($!)
    install_kyverno $GKE_CLUSTER_ID_PROV2 &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi


# Install Liqo
VERSION=6a04828e3b4b617de126df423c9f00cfe6fbe695
CHART="${HOME}/Documents/liqo/liqo/deployments/liqo"       # ""
if [[ $INSTALL_LIQO == true ]]; then
    PIDS=()
    install_liqo $GKE_CLUSTER_ID_CONS $GKE_CLUSTER_ZONE_CONS $VERSION $CHART &
    PIDS+=($!)
    install_liqo $GKE_CLUSTER_ID_PROV1 $GKE_CLUSTER_ZONE_PROV1 $VERSION $CHART &
    PIDS+=($!)
    install_liqo $GKE_CLUSTER_ID_PROV2 $GKE_CLUSTER_ZONE_PROV2 $VERSION $CHART &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi


# Delete GKE clusters
if [[ $DESTROY == true ]]; then
    PIDS=()
    gcloud container clusters delete $GKE_CLUSTER_ID_CONS --zone $GKE_CLUSTER_ZONE_CONS --project $GKE_PROJECT_ID --quiet &
    PIDS+=($!)
    gcloud container clusters delete $GKE_CLUSTER_ID_PROV1 --zone $GKE_CLUSTER_ZONE_PROV1 --project $GKE_PROJECT_ID --quiet &
    PIDS+=($!)
    gcloud container clusters delete $GKE_CLUSTER_ID_PROV2 --zone $GKE_CLUSTER_ZONE_PROV2 --project $GKE_PROJECT_ID --quiet &
    PIDS+=($!)
    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi