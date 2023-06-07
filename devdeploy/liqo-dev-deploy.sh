#!/usr/bin/env bash

FILEPATH=$(realpath "$0")
DIRPATH=$(dirname "$FILEPATH")
TAG="$(date +%s)"
LIQO_ROOT="${HOME}/Documents/liqo/liqo"
DEPLOY=true

COMPONENTS=(
    "controller-manager"
    "liqonet"
    "virtual-kubelet"
)

for COMPONENT in "${COMPONENTS[@]}"; do
    tput setaf 3; tput bold; echo "Component: ${COMPONENT}"
    tput sgr0

    IMAGE_BASE="localhost:5001/${COMPONENT}"
    IMAGE="${IMAGE_BASE}:${TAG}"
    export IMAGE

    # Build the image
    tput setaf 3; tput bold; echo "Building ${IMAGE}"
    tput sgr0

    if [[ "${COMPONENT}" == "liqonet" ]]; then
        docker build -t "${LIQONET_IMAGE}" --file="${LIQO_ROOT}/build/liqonet/Dockerfile" "${LIQO_ROOT}" || exit 1
        #docker buildx build --push --platform linux/amd64,linux/arm64 --tag "ghcr.io/cheina97/${COMPONENT}:${TAG}" --file="${LIQO_ROOT}/build/liqonet/Dockerfile" "${LIQO_ROOT}" || exit 1
    else
        docker build -t "${IMAGE}" --file="${LIQO_ROOT}/build/common/Dockerfile" --build-arg=COMPONENT="${COMPONENT}" "${LIQO_ROOT}" || exit 1
    fi
    docker tag "${IMAGE}" "${IMAGE_BASE}:latest"
    docker push "${IMAGE}"
    docker push "${IMAGE_BASE}:latest"

    if [[ "${DEPLOY}" == "false" ]]; then
        continue
    fi

    # Update the image in the cluster
    kind get clusters | while read line; do
        tput setaf 3; tput bold; echo "Updating ${COMPONENT} in cluster ${line} with image ${IMAGE}"
        tput sgr0

        export KUBECONFIG="${HOME}/liqo_kubeconf_${line}"
        if [[ "${COMPONENT}" == "liqonet" ]]; then
            envsubst <"${DIRPATH}/gateway-patch.yaml" | kubectl -n liqo patch deployment liqo-gateway --patch-file=/dev/stdin
            envsubst <"${DIRPATH}/networkmanager-patch.yaml" | kubectl -n liqo patch deployment liqo-network-manager --patch-file=/dev/stdin
        else
            PATCH_YAML="${DIRPATH}/${COMPONENT}-patch.yaml"
            PATCH_JSON="${DIRPATH}/${COMPONENT}-patch.json"
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
