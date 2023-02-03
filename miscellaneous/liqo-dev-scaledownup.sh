#!/usr/bin/env bash

kind get clusters| while read line; do
    export KUBECONFIG="${HOME}/liqo_kubeconf_${line}"
    kubectl -n liqo scale --replicas 0 deployment liqo-gateway
    kubectl -n liqo scale --replicas 0 deployment liqo-network-manager
done
echo

sleep 5s

kind get clusters| while read line; do
    export KUBECONFIG="${HOME}/liqo_kubeconf_${line}"
    kubectl -n liqo scale --replicas 1 deployment liqo-gateway
    kubectl -n liqo scale --replicas 1 deployment liqo-network-manager
done
echo



