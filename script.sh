#!/usr/bin/env bash

letters=(a b c d e f)

export  KUBECONFIG="$HOME/liqo_kubeconf_cluster1"
kubectl create namespace liqo-test-cluster1
liqoctl offload namespace liqo-test-cluster1 --pod-offloading-strategy Local --namespace-mapping-strategy EnforceSameName
for letter in "${letters[@]}"; do
    kubectl -n liqo-test-cluster1 create deployment "${letter}1" --image=ghcr.io/stefanprodan/podinfo --port=9898
    kubectl -n liqo-test-cluster1 expose deployment "${letter}1"
done

export  KUBECONFIG="$HOME/liqo_kubeconf_cluster2"
kubectl create namespace liqo-test-cluster2
liqoctl offload namespace liqo-test-cluster2 --pod-offloading-strategy Local --namespace-mapping-strategy EnforceSameName
for letter in "${letters[@]}"; do
    kubectl -n liqo-test-cluster2 create deployment "${letter}2" --image=ghcr.io/stefanprodan/podinfo --port=9898
    kubectl -n liqo-test-cluster2 expose deployment "${letter}2"
done

export KUBECONFIG="$HOME/liqo_kubeconf_cluster1"
for letter in "${letters[@]}"; do
    kubectl wait deployment "${letter}1" --for=condition=Available -n liqo-test-cluster1
done

export KUBECONFIG="$HOME/liqo_kubeconf_cluster2"
for letter in "${letters[@]}"; do
    kubectl wait deployment "${letter}2" --for=condition=Available -n liqo-test-cluster2
done

export  KUBECONFIG="$HOME/liqo_kubeconf_cluster1"
kubectl run curl --image=radial/busyboxplus:curl -- sleep 600
kubectl wait --for=condition=Ready pod/curl
for letter in "${letters[@]}"; do
    echo -n "curl  ${letter}2.liqo-test-cluster2.svc.cluster.local -> "
    kubectl exec curl --  curl -s -o /dev/null -w "%{http_code}" "${letter}2.liqo-test-cluster2.svc.cluster.local:9898"
    echo
done

export KUBECONFIG="$HOME/liqo_kubeconf_cluster2"
kubectl run curl --image=radial/busyboxplus:curl -- sleep 600
kubectl wait --for=condition=Ready pod/curl
for letter in "${letters[@]}"; do
    echo -n "curl  ${letter}1.liqo-test-cluster2.svc.cluster.local -> "
    kubectl exec curl --  curl -s -o /dev/null -w "%{http_code}" "${letter}1.liqo-test-cluster1.svc.cluster.local:9898"
    echo
done

export KUBECONFIG="$HOME/liqo_kubeconf_cluster1"
echo "Cleaning up cluster1"
kubectl delete pod curl
export KUBECONFIG="$HOME/liqo_kubeconf_cluster2"
echo "Cleaning up cluster2"
kubectl delete pod curl
