#!/usr/bin/env bash

export GKE_SERVICE_ACCOUNT_PATH="$HOME/.liqo/gcp_service_account"

PIDS=()

gcloud container clusters create --zone=europe-west1-b gke1 &
PIDS+=($!) 

gcloud container clusters create --zone=europe-west2-b gke2 &
PIDS+=($!)

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

PIDS=()

export KUBECONFIG="$HOME/liqo_kubeconf_gke1"
gcloud container clusters get-credentials gke1 --zone=europe-west1-b

export KUBECONFIG="$HOME/liqo_kubeconf_gke2"
gcloud container clusters get-credentials gke2 --zone=europe-west2-b

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

exit 0
export KUBECONFIG="$HOME/liqo_kubeconf_gke1"
liqoctl install gke --project-id liqo-test --machine-type "e2-small" --num-nodes "1" --cluster-id gke1 --zone=europe-west1-b --credentials-path ${GKE_SERVICE_ACCOUNT_PATH} &
PIDS+=($!)

export KUBECONFIG="$HOME/liqo_kubeconf_gke2"
liqoctl install gke --project-id liqo-test --machine-type "e2-small" --num-nodes "1" --cluster-id gke2 --zone=europe-west2-b --credentials-path ${GKE_SERVICE_ACCOUNT_PATH} &
PIDS+=($!)

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

echo
tput setaf 2; tput bold; echo "STARTED SUCCESSFULLY"
tput sgr0
echo

# liqoctl peer in-band --kubeconfig "$HOME/liqo_kubeconf_gke1" --remote-kubeconfig "$HOME/liqo_kubeconf_gke2" --bidirectional
