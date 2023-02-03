#!/usr/bin/env bash

PIDS=()

#eksctl create cluster --name eks-1 --version=1.23 --managed --spot --instance-types=c4.large,c5.large --region=eu-west-1 --kubeconfig "$HOME/liqo_kubeconf_eks-1" --node-ami-family=Ubuntu2004 &
eksctl create cluster --name eks-1 --version=1.23 --managed --spot --instance-types=c4.large,c5.large --region=eu-west-1 --kubeconfig "$HOME/liqo_kubeconf_eks-1" &
PIDS+=($!) 
#eksctl create cluster --name eks-2 --version=1.23 --managed --spot --instance-types=c4.large,c5.large --region=eu-west-2 --kubeconfig "$HOME/liqo_kubeconf_eks-2" --node-ami-family=Ubuntu2004 &
eksctl create cluster --name eks-2 --version=1.23 --managed --spot --instance-types=c4.large,c5.large --region=eu-west-2 --kubeconfig "$HOME/liqo_kubeconf_eks-2" &
PIDS+=($!)

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

PIDS=()

export EKS_CLUSTER_NAME=eks-1
export EKS_CLUSTER_REGION=eu-west-1
liqoctl install eks --eks-cluster-region=${EKS_CLUSTER_REGION} --eks-cluster-name=${EKS_CLUSTER_NAME} --kubeconfig "$HOME/liqo_kubeconf_eks-1" --user-name "liqo-cluster-francesco.cheinasso" &
PIDS+=($!)

export EKS_CLUSTER_NAME=eks-2
export EKS_CLUSTER_REGION=eu-west-2 
liqoctl install eks --eks-cluster-region=${EKS_CLUSTER_REGION} --eks-cluster-name=${EKS_CLUSTER_NAME} --kubeconfig "$HOME/liqo_kubeconf_eks-2" --user-name "liqo-cluster-francesco.cheinasso" &
PIDS+=($!)

for PID in "${PIDS[@]}"; do
    wait "$PID"
done

echo
tput setaf 2; tput bold; echo "STARTED SUCCESSFULLY"
tput sgr0
echo

# liqoctl peer in-band --kubeconfig "$HOME/liqo_kubeconf_eks-1" --remote-kubeconfig "$HOME/liqo_kubeconf_eks-2" --bidirectional