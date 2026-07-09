#!/bin/bash

set -e

# Parse arguments
N=""
while getopts "n:" opt; do
    case $opt in
    n) N="$OPTARG" ;;
    *)
        echo "Usage: $0 -n <number_of_clusters>"
        exit 1
        ;;
    esac
done

if [[ -z "$N" ]]; then
    echo "Error: -n flag is required"
    echo "Usage: $0 -n <number_of_clusters>"
    exit 1
fi

if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 ]]; then
    echo "Error: -n must be a positive integer"
    exit 1
fi

for i in $(seq 1 "$N"); do
    KUBECONFIG_PATH="$HOME/liqo-kubeconf-cheina-cluster${i}"
    if [[ ! -f "$KUBECONFIG_PATH" ]]; then
        echo "Warning: $KUBECONFIG_PATH not found, skipping"
        continue
    fi

    echo ">>> Deleting gateway pods on cluster${i} (${KUBECONFIG_PATH})"
    KUBECONFIG="$KUBECONFIG_PATH" kubectl delete pods \
        --all-namespaces \
        -l networking.liqo.io/component=gateway \
        --ignore-not-found
done
