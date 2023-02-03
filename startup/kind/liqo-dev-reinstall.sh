#!/usr/bin/env bash

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
    --disable-telemetry \
    --set gateway.config.wireguardImplementation="kernel" \
    --version v0.7.0

    #liqoctl install kind --timeout 60m --version 9f345fdfa30653103386f885b9bcf474ca4ef648 --cluster-name "$CLUSTER_NAME_ITEM" \
    #--local-chart-path $HOME/Documents/liqo/liqo/deployments/liqo \
    #--set gateway.metrics.enabled=true \
    #--set gateway.metrics.serviceMonitor.enabled="${serviceMonitorEnabled}" \
    #--disable-telemetry
}


CLUSTER_NAMES=()
while read -r CLUSTER_NAME_ITEM; do
    CLUSTER_NAMES+=("${CLUSTER_NAME_ITEM}")
done < <(kind get clusters)

for CLUSTER_NAME_ITEM in "${CLUSTER_NAMES[@]}"; do
    echo "Unpeering cluster ${CLUSTER_NAME_ITEM} from:"
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    kubectl get foreignclusters -A| tail -n +2 | while read -r line; do
        cluster_name=$(echo "$line" | tr -s ' ' | cut -d ' ' -f 1)
        peer_type=$(echo "$line" | tr -s ' ' | cut -d ' ' -f 2)
        echo "cluster ${cluster_name} of type ${peer_type}"
        case $peer_type in
            InBand)
                liqoctl unpeer in-band --remote-kubeconfig "$HOME/liqo_kubeconf_${cluster_name}" 
                ;;
            OutOfBand)
                liqoctl unpeer out-of-band "$cluster_name"
                ;;
        esac
    done
done

PIDS=()
for CLUSTER_NAME_ITEM in "${CLUSTER_NAMES[@]}"; do
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    liqoctl uninstall --purge &
    PIDS+=($!)
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

for CLUSTER_NAME_ITEM in "${CLUSTER_NAMES[@]}"; do
    echo "Waiting for namespace liqo to be deleted on cluster ${CLUSTER_NAME_ITEM}"
    while kubectl get namespace liqo &>/dev/null ; do
        sleep 1
    done 
done
sleep 1

PIDS=()
for CLUSTER_NAME_ITEM in "${CLUSTER_NAMES[@]}"; do
    export KUBECONFIG="$HOME/liqo_kubeconf_${CLUSTER_NAME_ITEM}"
    serviceMonitorEnabled="false"
    if [[ "${CLUSTER_NAME_ITEM}" == *"1"* ]]; then
        serviceMonitorEnabled="true"
    fi
    liqoctl_install_kind "${serviceMonitorEnabled}" "50" &
    PIDS+=($!)
done

for PID in "${PIDS[@]}"; do
    wait "$PID"
done
