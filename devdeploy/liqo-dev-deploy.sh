#!/usr/bin/env bash

TAG="$(date +%s)"
LIQONET_IMAGE="localhost:5001/liqonet:${TAG}"
CONTROLLER_MANAGER_IMAGE="localhost:5001/liqo-controller-manager:${TAG}"
VK_IMAGE="localhost:5001/virtual-kubelet:${TAG}"


#docker build -t "${LIQONET_IMAGE}" --file="${HOME}/Documents/liqo/liqo/build/liqonet/Dockerfile" "${HOME}/Documents/liqo/liqo" || exit 1
docker build -t "${CONTROLLER_MANAGER_IMAGE}" --file="${HOME}/Documents/liqo/liqo/build/common/Dockerfile" --build-arg=COMPONENT="liqo-controller-manager" "${HOME}/Documents/liqo/liqo" || exit 1
#docker build -t "${VK_IMAGE}" --file="${HOME}/Documents/liqo/liqo/build/common/Dockerfile" --build-arg=COMPONENT="virtual-kubelet" "${HOME}/Documents/liqo/liqo" || exit 1
echo

#docker push "${LIQONET_IMAGE}"
docker push "${CONTROLLER_MANAGER_IMAGE}"
#docker push "${VK_IMAGE}"
echo

kind get clusters| while read line; do
    export KUBECONFIG="${HOME}/liqo_kubeconf_${line}"
    #kubectl -n liqo patch deployment liqo-gateway --patch "{\"spec\": {\"template\": {\"spec\": {\"containers\": [{\"name\": \"gateway\",\"image\": \"${LIQONET_IMAGE}\", liqo\"args\": [ \"-v=1\", \"--run-as=liqo-gateway\", \"--gateway.leader-elect=true\", \"--gateway.mtu=1340\", \"--gateway.listening-port=5871\", \"--metrics-bind-addr=:5872\", \"--gateway.ping-interval=200ms\", \"--gateway.ping-loss-threshold=10\", \"--gateway.ping-latency-update-interval=1s\" ]}]}}}}"
    #kubectl -n liqo patch deployment liqo-network-manager --patch "{\"spec\": {\"template\": {\"spec\": {\"containers\": [{\"name\": \"network-manager\",\"image\": \"${LIQONET_IMAGE}\"}]}}}}"
    kubectl -n liqo patch deployment liqo-controller-manager --patch "{\"spec\": {\"template\": {\"spec\": {\"containers\": [{\"name\": \"controller-manager\",\"image\": \"${CONTROLLER_MANAGER_IMAGE}\"}]}}}}"
done
echo

kind get clusters| while read cluster_name; do
    export KUBECONFIG="${HOME}/liqo_kubeconf_${cluster_name}"
    tput setaf 3; tput bold; echo "${cluster_name} downloading containers ..."
    tput sgr0
    kubectl wait deployment -n liqo liqo-gateway --for condition=Available=True --timeout=300s
    kubectl wait deployment -n liqo liqo-network-manager --for condition=Available=True --timeout=300s
    kubectl wait deployment -n liqo liqo-controller-manager --for condition=Available=True --timeout=300s
done

echo
tput setaf 2; tput bold; echo "LIQONET BUILT AND DEPLOYED SUCCESSFULLY"
tput sgr0
echo
