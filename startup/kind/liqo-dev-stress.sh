#!/usr/bin/env bash

export KUBECONFIG="$HOME/liqo-kubeconf-cheina-cluster1"

while getopts "l:" opt; do
    case $opt in
        l) LOOPS=$OPTARG ;;
        *) echo "Usage: $0 [-l loops]" >&2; exit 1 ;;
    esac
done

if [ -z "$LOOPS" ]; then
    echo "Error: -l flag is required" >&2
    echo "Usage: $0 [-l loops]" >&2
    exit 1
fi


for ((j=1; j<=LOOPS; j++)); do
    echo "Iteration $j"

    PIDS=()
    for i in {2..3}; do
        liqoctl peer --remote-kubeconfig "$HOME/liqo-kubeconf-cheina-cluster${i}" --server-service-type NodePort --mtu 1500 &
        PIDS+=($!)
    done

    for PID in "${PIDS[@]}"; do
        wait "${PID}"
    done

    echo

    liqoctl test network -p "${HOME}/liqo-kubeconf-cheina-cluster2,${HOME}/liqo-kubeconf-cheina-cluster3" --np-nodes all --np-ext --pod-np --ip --rm
    if [ $? -ne 0 ]; then
        echo "liqoctl test network command failed" >&2
        exit 1
    fi

    echo

    PIDS=()
    for i in {2..3}; do
        liqoctl unpeer --remote-kubeconfig "$HOME/liqo-kubeconf-cheina-cluster${i}" &
        PIDS+=($!)
    done

    for PID in "${PIDS[@]}"; do
        wait "${PID}"
    done
done