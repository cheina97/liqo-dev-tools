#!/usr/bin/env bash

export KUBECONFIG="${HOME}/liqo-kubeconf-cheina-cluster1"

for i in $(seq 2 3); do
    liqoctl peer --remote-kubeconfig "${HOME}/liqo-kubeconf-cheina-cluster${i}" --server-service-type NodePort --mtu 1500   
done