#!/usr/bin/env bash

cnis=(
    #"cilium"
    #"calico"
    "flannel"
)

podcidrtypes=(
    #overlapped
    nonoverlapped
)

for podcidrtype in "${podcidrtypes[@]}"; do
    for cni in "${cnis[@]}"; do
        NodePortFlagValue="all"
        if [ "${cni}" == "flannel" ]; then
            NodePortFlagValue="workers"
        fi

        consumername="cluster-1-${cni}-${podcidrtype}-rocky"
        consumerkubeconfig="${HOME}/${consumername}"
        
        providerkubeconfigs="${HOME}/cluster-2-${cni}-${podcidrtype}-rocky,${HOME}/cluster-3-${cni}-${podcidrtype}-rocky"

        echo "Running test for ${cni} with ${podcidrtype} podcidr"
        liqo-connectivity-test -c "${consumerkubeconfig}" -p "${providerkubeconfigs}" --np-nodes "${NodePortFlagValue}" --np-ext
        if [ $? -ne 0 ]; then
            echo "Test failed"
            exit 1
        fi

        kubectl delete po -A --selector networking.liqo.io/component=gateway --kubeconfig "${consumerkubeconfig}"
        kubectl wait --for=condition=ready po -A --selector networking.liqo.io/component=gateway --kubeconfig "${consumerkubeconfig}" --timeout=5m

        kubectl delete po -A --selector networking.liqo.io/component=gateway --kubeconfig "${HOME}/cluster-2-${cni}-${podcidrtype}-rocky"
        kubectl wait --for=condition=ready po -A --selector networking.liqo.io/component=gateway --kubeconfig "${HOME}/cluster-2-${cni}-${podcidrtype}-rocky" --timeout=5m

        kubectl delete po -A --selector networking.liqo.io/component=gateway --kubeconfig "${HOME}/cluster-3-${cni}-${podcidrtype}-rocky"
        kubectl wait --for=condition=ready po -A --selector networking.liqo.io/component=gateway --kubeconfig "${HOME}/cluster-3-${cni}-${podcidrtype}-rocky" --timeout=5m

        sleep 30s

        liqo-connectivity-test -c "${consumerkubeconfig}" -p "${providerkubeconfigs}" --np-nodes "${NodePortFlagValue}" --np-ext
        if [ $? -ne 0 ]; then
            echo "Test failed"
            exit 1
        fi

        kubectl delete po -n liqo --all --kubeconfig "${HOME}/cluster-2-${cni}-${podcidrtype}-rocky"
        sleep 2s
        kubectl wait --for=condition=ready po -n liqo --selector app.kubernetes.io/part-of=liqo --kubeconfig "${HOME}/cluster-2-${cni}-${podcidrtype}-rocky" --timeout=5m

        kubectl delete po -n liqo --all --kubeconfig "${HOME}/cluster-3-${cni}-${podcidrtype}-rocky"
        sleep 2s
        kubectl wait --for=condition=ready po -n liqo --selector app.kubernetes.io/part-of=liqo --kubeconfig "${HOME}/cluster-3-${cni}-${podcidrtype}-rocky" --timeout=5m

        kubectl delete po -n liqo --all --kubeconfig "${consumerkubeconfig}"
        sleep 2s
        kubectl wait --for=condition=ready po -n liqo --selector app.kubernetes.io/part-of=liqo --kubeconfig "${consumerkubeconfig}" --timeout=5m

        sleep 30s

        liqo-connectivity-test -c "${consumerkubeconfig}" -p "${providerkubeconfigs}" --np-nodes "${NodePortFlagValue}" --np-ext
        if [ $? -ne 0 ]; then
            echo "Test failed"
            exit 1
        fi

    done
done