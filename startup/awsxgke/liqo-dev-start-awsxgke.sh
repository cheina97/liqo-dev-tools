#!/usr/bin/env bash

export GKE_SERVICE_ACCOUNT_PATH="$HOME/.liqo/gcp_service_account"

PIDS=()

#eksctl create cluster --name eks1 --version=1.23 --managed --spot --instance-types=c4.large,c5.large --region=eu-west-1 --kubeconfig "$HOME/liqo-kubeconf-eks1" --node-ami-family=Ubuntu2004 &
eksctl create cluster --name eks1 --version=1.23 --managed --spot --instance-types=c4.large,c5.large --region=eu-west-1 --kubeconfig "$HOME/liqo-kubeconf-eks1" &
PIDS+=($!) 

gcloud container clusters create --zone=europe-west1-b gke1 &
PIDS+=($!) 

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

PIDS=()

export KUBECONFIG="$HOME/liqo-kubeconf-gke1"
gcloud container clusters get-credentials gke1 --zone=europe-west1-b

PIDS=()

export EKS_CLUSTER_NAME=eks1
export EKS_CLUSTER_REGION=eu-west-1
liqoctl install eks --eks-cluster-region=${EKS_CLUSTER_REGION} --eks-cluster-name=${EKS_CLUSTER_NAME} --kubeconfig "$HOME/liqo-kubeconf-eks1" --user-name "liqo-cluster-francesco.cheinasso" &
PIDS+=($!)

export KUBECONFIG="$HOME/liqo-kubeconf-gke1"
liqoctl install gke --project-id liqo-test --cluster-id gke1 --zone=europe-west1-b --credentials-path "${GKE_SERVICE_ACCOUNT_PATH}" &
PIDS+=($!)

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

echo
tput setaf 2; tput bold; echo "STARTED SUCCESSFULLY"
tput sgr0
echo

# liqoctl peer in-band --kubeconfig "$HOME/liqo-kubeconf-eks1" --remote-kubeconfig "$HOME/liqo-kubeconf-gke1" --bidirectional
