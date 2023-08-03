#!/usr/bin/env bash

set -e 
set -u

FILEPATH=$(realpath "$0")
DIRPATH=$(dirname "$FILEPATH")
export DIRPATH

cluster_name="$1"

export KUBECONFIG="$HOME/liqo_kubeconf_${cluster_name}" 

kubectl apply -f "$DIRPATH/deploy/liqo-gateway.yaml"
kubectl wait --for=condition=available deployment/liqo-gateway --timeout=600s

kubectl apply -f "$DIRPATH/deploy/liqo-route.yaml"
kubectl wait --for=condition=available deployment/liqo-route --timeout=600s
