#!/usr/bin/env bash

PIDS=()

doctl kubernetes cluster create doks-1 --size s-1vcpu-2gb --count 1 --region ams3 &
PIDS+=($!)
doctl kubernetes cluster create doks-2 --size s-1vcpu-2gb --count 2 --region fra1 &
PIDS+=($!)

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

sleep 5s

doctl kubernetes cluster kubeconfig show doks-1 > "$HOME/liqo_kubeconfig_do1.yaml"
doctl kubernetes cluster kubeconfig show doks-2 > "$HOME/liqo_kubeconfig_do2.yaml"


liqo1podcidr=$(doctl kubernetes cluster get doks-1 --verbose -o json|jq ".[0].cluster_subnet" | cut -d "\"" -f 2)
liqo1servicecidr=$(doctl kubernetes cluster get doks-1 --verbose -o json|jq ".[0].service_subnet" | cut -d "\"" -f 2)

liqo2podcidr=$(doctl kubernetes cluster get doks-2 --verbose -o json|jq ".[0].cluster_subnet" | cut -d "\"" -f 2)
liqo2servicecidr=$(doctl kubernetes cluster get doks-2 --verbose -o json|jq ".[0].service_subnet" | cut -d "\"" -f 2)

PIDS=()

export KUBECONFIG="$HOME/liqo_kubeconfig_do1.yaml"
liqoctl install --pod-cidr "$liqo1podcidr" --service-cidr "$liqo1servicecidr" --cluster-name doks-1 &
PIDS+=($!)

export KUBECONFIG="$HOME/liqo_kubeconfig_do2.yaml"
liqoctl install --pod-cidr "$liqo2podcidr" --service-cidr "$liqo2servicecidr" --cluster-name doks-2 &
PIDS+=($!)

sleep 40s

export KUBECONFIG="$HOME/liqo_kubeconfig_do1.yaml"
kubectl wait --for=condition=ready pod  -l app.kubernetes.io/instance=liqo-gateway -n liqo
kubectl patch -n liqo services liqo-gateway --patch-file liqo-gateway-svc-patch.yaml
kubectl patch -n liqo deployments.apps liqo-gateway --patch-file liqo-gateway-deploy-patch.yaml

export KUBECONFIG="$HOME/liqo_kubeconfig_do2.yaml"
kubectl wait --for=condition=ready pod  -l app.kubernetes.io/instance=liqo-gateway -n liqo
kubectl patch -n liqo services liqo-gateway --patch-file liqo-gateway-svc-patch.yaml
kubectl patch -n liqo deployments.apps liqo-gateway --patch-file liqo-gateway-deploy-patch.yaml

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

echo
tput setaf 2; tput bold; echo "FINISHED SUCCESSFULLY"
tput sgr0
echo

