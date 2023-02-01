#!/usr/bin/env bash

export KUBECONFIG="$HOME/liqo_kubeconfig_do1.yaml"
kubectl create deployment --image nginx lb-replier -n liqo
kubectl patch service liqo-gateway --patch-file ./fix.sh -n liqo