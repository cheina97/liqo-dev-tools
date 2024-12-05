#!/usr/bin/env bash

FOLLOW=false
while getopts 'fh' flag; do
  case "$flag"  in
  f)
    FOLLOW=true
    ;;
  h) 
    help
    exit 0
    ;;
  *)
    help
    exit 1
    ;;
  esac
done

# Check if the graphviz directory exists, if not create it
if [ ! -d "graphviz" ]; then
  mkdir graphviz
fi

if $FOLLOW; then
    while true; do
      podname=$(kubectl get po -n liqo |grep ipam|cut -d " " -f 1)
      echo $podname
      kubectl cp -n liqo "${podname}:graphviz" ./graphviz/
      echo "Copied graphviz files from the ipam pod"
      find graphviz/. -type f
      echo
      sleep 1
    done
fi

podname=$(kubectl get po -n liqo |grep ipam|cut -d " " -f 1)
kubectl cp -n liqo "${podname}:graphviz" ./graphviz/
echo "Copied graphviz files from the ipam pod"
find graphviz/. -type f
