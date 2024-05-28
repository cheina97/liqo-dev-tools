#!/usr/bin/env bash

function peer () {
    cni=$1
    podcidrtype=$2

    consumername="cluster-1-${cni}-${podcidrtype}-ubuntu"
    consumerkubeconfig="${HOME}/${consumername}"

    for i in {2..3}; do
        echo "Peer cluster-${i}-${cni}-${podcidrtype}-ubuntu to ${consumername}"
        providername="cluster-${i}-${cni}-${podcidrtype}-ubuntu"
        providerkubeconfig="${HOME}/${providername}"
        cmd=$(KUBECONFIG=${providerkubeconfig} liqoctl generate peer-command --only-command) && eval "KUBECONFIG=${consumerkubeconfig} $cmd"
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
        peer "${cni}" "${podcidrtype}"
    done
done