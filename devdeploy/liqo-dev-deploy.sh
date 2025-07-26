#!/usr/bin/env bash

FILEPATH=$(realpath "$0")
PATCHDIRPATH=$(dirname "$FILEPATH")/patch

function help() {
    echo "Usage: "
    echo "  liqo-dev-start [-c component] [-b] [-t tag]"
    echo "Flags:"
    echo "  -h  - help"
    echo "  -c  - component to build (values: all,controller-manager,virtual-kubelet,liqonet,metric-agent,gateway,gateway/wireguard)"
    echo "  -b  - build only, do not deploy"
    echo "  -t  - specify tag to use (default: current timestamp)"
}

COMPONENTS=(
    "controller-manager"
    "virtual-kubelet"
    "liqonet"
    "metric-agent"
    "gateway"
    "gateway/wireguard"
    "gateway/geneve"
    "ipam"
    "fabric"
)
ALL_COMPONENTS=(
    "controller-manager"
    "virtual-kubelet"
    "liqonet"
    "metric-agent"
    "gateway"
    "gateway/wireguard"
    "gateway/geneve"
    "ipam"
    "fabric"
)

BUILD_ONLY=false
TAG="$(date +%s)"

# Parse flags
while getopts 'c:bt:ha' flag; do
    case "$flag" in
    c)
        IFS="," read -r -a COMPONENTS <<<"${OPTARG}"
        ;;
    b)
        BUILD_ONLY=true
        ;;
    t)
        TAG="${OPTARG}"
        ;;
    a)
        COMPONENTS=("${ALL_COMPONENTS[@]}")
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

LIQO_ROOT="${HOME}/Documents/liqo/liqo"
#FIXEDLIQONETIMAGE="localhost:5001/liqonet:1687872687"
#FIXEDVKIMAGE="localhost:5001/virtual-kubelet:1688721308"
#FIXEDCTRLMGRIMAGE="localhost:5001/controller-manager:1687872687"
#FIXEDMETRICIMAGE="localhost:5001/metric-agent:1687872687"
#FIXEDGATEWAYIMAGE="localhost:5001/gateway:1687872687"
#FIXEDWGGATEWAYIMAGE="localhost:5001/wg-gateway:1687872687"

echo "Building components: ${COMPONENTS[*]}"

export DOCKER_REGISTRY="localhost:5001"
export DOCKER_ORGANIZATION="liqotech"
export DOCKER_TAG="${TAG}"
export DOCKER_PUSH="true"
export ARCHS="${ARCHS:-linux/arm64}"

BUILD_CMD="$LIQO_ROOT/build/liqo/build.sh"

for COMPONENT in "${COMPONENTS[@]}"; do
    pushd "$LIQO_ROOT" || exit

    IMAGE_BASE="${DOCKER_REGISTRY}/${DOCKER_ORGANIZATION}/${COMPONENT}-ci"
    export IMAGE="${IMAGE_BASE}:${DOCKER_TAG}"

    if [[ "${COMPONENT}" == "controller-manager" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/liqo-controller-manager"
    elif [[ "${COMPONENT}" == "virtual-kubelet" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/virtual-kubelet"
    elif [[ "${COMPONENT}" == "metric-agent" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/metric-agent"
    elif [[ "${COMPONENT}" == "liqonet" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/liqonet"
    elif [[ "${COMPONENT}" == "gateway" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/gateway"
    elif [[ "${COMPONENT}" == "gateway/wireguard" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/gateway/wireguard"
    elif [[ "${COMPONENT}" == "gateway/geneve" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/gateway/geneve"
    elif [[ "${COMPONENT}" == "fabric" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/fabric"
    elif [[ "${COMPONENT}" == "ipam" ]]; then
        "$BUILD_CMD" "$LIQO_ROOT/cmd/ipam"
    else
        echo "Unknown component: ${COMPONENT}"
        continue
    fi

    popd || exit

    if [ "$BUILD_ONLY" = true ]; then
        continue
    fi

    # Update the image in the cluster
    kind get clusters | grep cheina | while read line; do
        tput setaf 3
        tput bold
        echo "Updating ${COMPONENT} in cluster ${line} with image ${IMAGE}"
        tput sgr0

        export KUBECONFIG="${HOME}/liqo-kubeconf-${line}"
        if [[ "${COMPONENT}" == "virtual-kubelet" ]]; then
            PATCH_YAML="${PATCHDIRPATH}/${COMPONENT}-patch.yaml"
            envsubst <"${PATCH_YAML}" | kubectl -n liqo patch vkoptionstemplate virtual-kubelet-default --type merge --patch-file=/dev/stdin
        elif [[ "${COMPONENT}" == "gateway" ]]; then
            envsubst <"${PATCHDIRPATH}/gateway-patch.json" | kubectl -n liqo patch wggatewayservertemplate wireguard-server --patch-file=/dev/stdin --type json
            envsubst <"${PATCHDIRPATH}/gateway-patch.json" | kubectl -n liqo patch wggatewayclienttemplate wireguard-client --patch-file=/dev/stdin --type json
        elif [[ "${COMPONENT}" == "gateway/wireguard" ]]; then
            envsubst <"${PATCHDIRPATH}/gateway-wireguard-patch.json" | kubectl -n liqo patch wggatewayservertemplate wireguard-server --patch-file=/dev/stdin --type json
            envsubst <"${PATCHDIRPATH}/gateway-wireguard-patch.json" | kubectl -n liqo patch wggatewayclienttemplate wireguard-client --patch-file=/dev/stdin --type json
        elif [[ "${COMPONENT}" == "gateway/geneve" ]]; then
            envsubst <"${PATCHDIRPATH}/gateway-geneve-patch.json" | kubectl -n liqo patch wggatewayservertemplate wireguard-server --patch-file=/dev/stdin --type json
            envsubst <"${PATCHDIRPATH}/gateway-geneve-patch.json" | kubectl -n liqo patch wggatewayclienttemplate wireguard-client --patch-file=/dev/stdin --type json
        elif [[ "${COMPONENT}" == "fabric" ]]; then
            envsubst <"${PATCHDIRPATH}/fabric-patch.yaml" | kubectl -n liqo patch daemonset liqo-fabric --patch-file=/dev/stdin
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
