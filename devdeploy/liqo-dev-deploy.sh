#!/usr/bin/env bash

FILEPATH=$(realpath "$0")
PATCHDIRPATH=$(dirname "$FILEPATH")/patch

function help() {
  echo "Usage: "
  echo "  liqo-dev-start [-c component] [-b]"
  echo "Flags:"
  echo "  -h  - help"
  echo "  -c  - component to build (values: all,controller-manager,virtual-kubelet,liqonet,metric-agent,gateway,gateway/wireguard)"
  echo "  -b  - build without deploying"
}

DEPLOY=true

COMPONENTS=(
    #"controller-manager"
    #"virtual-kubelet"
    #"liqonet"
    #"metric-agent"
    "gateway"
    "gateway/wireguard"
)

# Parse flags

while getopts 'c:bh' flag; do
  case "$flag" in
  c)
    echo "Selected components: ${OPTARG}"
    IFS="," read -r -a COMPONENTS <<< "${OPTARG}"
    ;;
  b)
    DEPLOY="false"
    echo "Building without deploying"
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

TAG="$(date +%s)"
LIQO_ROOT="${HOME}/Documents/liqo/liqo"
#FIXEDLIQONETIMAGE="localhost:5001/liqonet:1687872687"
#FIXEDVKIMAGE="localhost:5001/virtual-kubelet:1688721308"
#FIXEDCTRLMGRIMAGE="localhost:5001/controller-manager:1687872687"
#FIXEDMETRICIMAGE="localhost:5001/metric-agent:1687872687"
#FIXEDGATEWAYIMAGE="localhost:5001/gateway:1687872687"
#FIXEDWGGATEWAYIMAGE="localhost:5001/wg-gateway:1687872687"

noti -k -t "Liqo Build :toolbox:" -m "Cheina started building components: ${COMPONENTS[*]}"

echo "Building components: ${COMPONENTS[*]}"

for COMPONENT in "${COMPONENTS[@]}"; do
    tput setaf 3
    tput bold
    echo "Component: ${COMPONENT}"
    tput sgr0

    IMAGE_BASE="localhost:5001/${COMPONENT}"
    IMAGE="${IMAGE_BASE}:${TAG}"
    SKIPPUSH=false
    export IMAGE

    # Build the image
    tput setaf 3
    tput bold
    echo "Building ${IMAGE}"
    tput sgr0

    if [[ "${COMPONENT}" == "liqonet" ]]; then
        if [[ -z "${FIXEDLIQONETIMAGE}" ]]; then
            docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/liqonet/Dockerfile" "${LIQO_ROOT}" || exit 1
            #docker buildx build --push --platform linux/amd64,linux/arm64 --tag "ghcr.io/cheina97/${COMPONENT}:${TAG}" --file="${LIQO_ROOT}/build/liqonet/Dockerfile" "${LIQO_ROOT}" || exit 1
        else
            IMAGE="${FIXEDLIQONETIMAGE}"
            SKIPPUSH=true
        fi
    elif [[ "${COMPONENT}" == "controller-manager" ]]; then
        if [[ -z "${FIXEDCTRLMGRIMAGE}" ]]; then
            docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/common/Dockerfile" --build-arg=COMPONENT="liqo-${COMPONENT}" "${LIQO_ROOT}" || exit 1
        else
            IMAGE="${FIXEDCTRLMGRIMAGE}"
            SKIPPUSH=true
        fi
    elif [[ "${COMPONENT}" == "virtual-kubelet" ]]; then
        if [[ -z "${FIXEDVKIMAGE}" ]]; then
            docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/common/Dockerfile" --build-arg=COMPONENT="${COMPONENT}" "${LIQO_ROOT}" || exit 1
        else
            IMAGE="${FIXEDVKIMAGE}"
            SKIPPUSH=true
        fi
    elif [[ "${COMPONENT}" == "metric-agent" ]]; then
        docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/common/Dockerfile" --build-arg=COMPONENT="${COMPONENT}" "${LIQO_ROOT}" || exit 1
    elif [[ "${COMPONENT}" == "gateway" ]]; then
        docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/gateway/Dockerfile" "${LIQO_ROOT}" || exit 1
    elif [[ "${COMPONENT}" == "gateway/wireguard" ]]; then
        docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/gateway/wireguard/Dockerfile" "${LIQO_ROOT}" || exit 1
    else
        IMAGE="${FIXEDMETRICIMAGE}"
        SKIPPUSH=true
    fi

    if [[ "${SKIPPUSH}" == "false" ]]; then
        docker tag "${IMAGE}" "${IMAGE_BASE}:latest"
        docker push "${IMAGE}"
        docker push "${IMAGE_BASE}:latest"
    fi

    if [[ "${DEPLOY}" == "false" ]]; then
        continue
    fi

    # Update the image in the cluster
    kind get clusters| grep cheina | while read line; do
        tput setaf 3
        tput bold
        echo "Updating ${COMPONENT} in cluster ${line} with image ${IMAGE}"
        tput sgr0

        export KUBECONFIG="${HOME}/liqo_kubeconf_${line}"
        if [[ "${COMPONENT}" == "liqonet" ]]; then
            envsubst <"${PATCHDIRPATH}/gateway-patch.yaml" | kubectl -n liqo patch deployment liqo-legacy-gateway --patch-file=/dev/stdin
            envsubst <"${PATCHDIRPATH}/network-manager-patch.yaml" | kubectl -n liqo patch deployment liqo-network-manager --patch-file=/dev/stdin
            envsubst <"${PATCHDIRPATH}/route-patch.yaml" | kubectl -n liqo patch daemonsets liqo-route --patch-file=/dev/stdin
            #kubectl set env -n liqo deployment/liqo-gateway WIREGUARD_IMPLEMENTATION=userspace
            #kubectl set env -n liqo deployment/liqo-gateway IPTABLES_MODE=nf_tables
            #kubectl set env -n liqo deployment/liqo-network-manager IPTABLES_MODE=nf_tables
            #kubectl set env -n liqo daemonset/liqo-route IPTABLES_MODE=nf_tables

        elif [[ "${COMPONENT}" == "virtual-kubelet" ]]; then
            PATCH_JSON="${PATCHDIRPATH}/${COMPONENT}-patch.json"
            envsubst <"${PATCH_JSON}" | kubectl -n liqo patch deployment liqo-controller-manager --patch-file=/dev/stdin --type json
        elif [[ "${COMPONENT}" == "gateway" ]]; then
            envsubst <"${PATCHDIRPATH}/gateway-patch.json" | kubectl -n liqo patch wggatewayservertemplate  wireguard-server --patch-file=/dev/stdin --type json
            envsubst <"${PATCHDIRPATH}/gateway-patch.json" | kubectl -n liqo patch wggatewayclienttemplate  wireguard-client --patch-file=/dev/stdin --type json
        elif [[ "${COMPONENT}" == "gateway/wireguard" ]]; then
            envsubst <"${PATCHDIRPATH}/gateway-wireguard-patch.json" | kubectl -n liqo patch wggatewayservertemplate  wireguard-server --patch-file=/dev/stdin --type json
            envsubst <"${PATCHDIRPATH}/gateway-wireguard-patch.json" | kubectl -n liqo patch wggatewayclienttemplate  wireguard-client --patch-file=/dev/stdin --type json
        else
            PATCH_YAML="${PATCHDIRPATH}/${COMPONENT}-patch.yaml"
            PATCH_JSON="${PATCHDIRPATH}/${COMPONENT}-patch.json"
            if [ -f "${PATCH_YAML}" ]; then
                envsubst <"${PATCH_YAML}" | kubectl -n liqo patch deployment "liqo-${COMPONENT}" --patch-file=/dev/stdin
            fi
            if [ -f "${PATCH_JSON}" ]; then
                envsubst <"${PATCH_JSON}" | kubectl -n liqo patch deployment "liqo-${COMPONENT}" --patch-file=/dev/stdin --type json
            fi
        fi
    done
done

echo
tput setaf 2
tput bold
echo "LIQONET BUILT AND DEPLOYED"
tput sgr0
echo

noti -k -t "Liqo Build :toolbox:" -m "Cheina images built and deployed :white_check_mark:"
