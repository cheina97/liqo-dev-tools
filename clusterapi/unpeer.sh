#!/usr/bin/env bash

function unpeer () {
    cni=$1
    podcidrtype=$2

    consumername="cluster-1-${cni}-${podcidrtype}-rocky"
    consumerkubeconfig="${HOME}/${consumername}"

    for i in {2..3}; do
        providername="cluster-${i}-${cni}-${podcidrtype}-rocky"
        KUBECONFIG=${consumerkubeconfig} liqoctl unpeer out-of-band "${providername}" --skip-confirm
    done
}


cnis=(
    "cilium"
    #"calico"
    #"flannel"
)

podcidrtypes=(
    #overlapped
    nonoverlapped
)

for podcidrtype in "${podcidrtypes[@]}"; do
    for cni in "${cnis[@]}"; do
        unpeer "${cni}" "${podcidrtype}" 
    done
done