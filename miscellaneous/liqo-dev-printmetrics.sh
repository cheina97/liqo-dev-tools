#!/usr/bin/env bash

export KUBECONFIG="$HOME/liqo-kubeconf-cluster1"
kubectl exec deployments/liqo-gateway -n liqo -- ip link set lo up
while true ; do
    kubectl exec deployments/liqo-gateway -n liqo -- wget -qO- localhost:5872/metrics |grep liqo
    sleep 2
    clear
done


