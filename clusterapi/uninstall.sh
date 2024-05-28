#!/usr/bin/env bash

function liqouninstall (){
    index=$1
    cni=$2
    podcidrtype=$3

    name="cluster-${index}-${cni}-${podcidrtype}-rocky"
    kubeconfig="${HOME}/${name}"

    #Check if liqo is not installed with helm and if it is, skip the uninstaller.
    if ! helm status --kubeconfig "${kubeconfig}" -n liqo liqo &> /dev/null; then
        echo "Cluster ${name} liqo not installed"
        return
    fi

    echo "Installing Liqo on cluster ${name}"
    KUBECONFIG="$kubeconfig" liqoctl uninstall --purge --skip-confirm
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
        for i in {1..3}; do
            liqouninstall "${i}" "${cni}" "${podcidrtype}"
        done
    done
done


