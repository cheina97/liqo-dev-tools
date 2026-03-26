#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Label to identify containers created by kind-scale
KIND_SCALE_LABEL="io.kindscale.managed=true"

# Default values
CLUSTER_NAME="kind"
ACTION=""
NODE_NAME=""
WAIT_READY=false

# Function to display usage
usage() {
    echo "Usage: $0 <add|remove|clean> [options]"
    echo ""
    echo "Commands:"
    echo "  add <node-name>     Add a new node to the cluster"
    echo "  remove <node-name>  Remove a node from the cluster"
    echo "  clean               Remove all nodes created by kind-scale (optionally filtered by cluster)"
    echo ""
    echo "Options:"
    echo "  -c, --cluster <name>  Specify the cluster name (default: kind)"
    echo "  -w, --wait            Wait for the node to become Ready in Kubernetes (add only)"
    echo ""
    echo "Examples:"
    echo "  $0 add worker2 -c my-cluster"
    echo "  $0 add worker2 -c my-cluster --wait"
    echo "  $0 remove worker2 --cluster my-cluster"
    echo "  $0 clean -c my-cluster"
    echo "  $0 clean  # Clean all kind-scale nodes from all clusters"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    add | remove | clean)
        ACTION="$1"
        shift
        if [[ "$ACTION" != "clean" && -n "$1" && "$1" != -* ]]; then
            NODE_NAME="$1"
            shift
        fi
        ;;
    -c | --cluster)
        CLUSTER_NAME="$2"
        shift 2
        ;;
    -w | --wait)
        WAIT_READY=true
        shift
        ;;
    -h | --help)
        usage
        ;;
    *)
        echo "Error: Unknown option '$1'"
        usage
        ;;
    esac
done

# Validate action
if [[ -z "$ACTION" ]]; then
    echo "Error: No action specified."
    usage
fi

if [[ "$ACTION" != "clean" && -z "$NODE_NAME" ]]; then
    echo "Error: Node name is required for '$ACTION' action."
    usage
fi

# For add/remove actions, check if the control plane exists and set kubeconfig
if [[ "$ACTION" != "clean" ]]; then
    CONTROL_PLANE="${CLUSTER_NAME}-control-plane"
    if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTROL_PLANE}$"; then
        echo "Error: Control plane container '${CONTROL_PLANE}' not found. Is the cluster running?"
        exit 1
    fi

    # Set KUBECONFIG to the cluster's kubeconfig file
    export KUBECONFIG="$HOME/liqo-kubeconf-${CLUSTER_NAME}"
    if [[ ! -f "$KUBECONFIG" ]]; then
        echo "Warning: Kubeconfig file not found at $KUBECONFIG"
        echo "         Attempting to generate it..."
        kind get kubeconfig --name "${CLUSTER_NAME}" >"$KUBECONFIG" 2>/dev/null || {
            echo "Error: Could not generate kubeconfig for cluster '${CLUSTER_NAME}'"
            exit 1
        }
    fi
fi

if [[ "$ACTION" == "add" ]]; then
    FULL_NODE_NAME="${CLUSTER_NAME}-${NODE_NAME}"
    echo "Adding node '${NODE_NAME}' to cluster '${CLUSTER_NAME}'..."

    # 1. Dynamically get the network and image from the control plane
    NETWORK=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "${CONTROL_PLANE}" | head -n 1)
    IMAGE=$(docker inspect --format='{{.Config.Image}}' "${CONTROL_PLANE}")

    echo " -> Using network: ${NETWORK}"
    echo " -> Using image: ${IMAGE}"

    # 2. Get the kubeadm join command
    echo " -> Generating kubeadm join token..."
    JOIN_CMD=$(docker exec "${CONTROL_PLANE}" kubeadm token create --print-join-command)

    # 3. Start the new Docker container
    echo " -> Starting Docker container for ${FULL_NODE_NAME}..."
    docker run -d \
        --name "${FULL_NODE_NAME}" \
        --hostname "${FULL_NODE_NAME}" \
        --label "${KIND_SCALE_LABEL}" \
        --label "io.kindscale.cluster=${CLUSTER_NAME}" \
        --privileged \
        --network "${NETWORK}" \
        --tmpfs /tmp \
        --tmpfs /run \
        --volume /var \
        --volume /lib/modules:/lib/modules:ro \
        "${IMAGE}" >/dev/null

    # 3.5 Wait for containerd to initialize
    echo " -> Waiting for containerd to start..."
    until docker exec "${FULL_NODE_NAME}" test -S /var/run/containerd/containerd.sock; do
        sleep 1
    done
    # Give it one extra second to ensure the CRI is fully responsive
    sleep 1

    # 3.6 Configure containerd registry mirrors (for localhost:5001 and proxies)
    echo " -> Configuring containerd registry mirrors..."
    docker exec "${FULL_NODE_NAME}" bash -c 'cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["http://kind-registry-proxy-dh:5000"]
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
  endpoint = ["http://kind-registry-proxy-ghcr:5000"]
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
  endpoint = ["http://kind-registry-proxy-quay:5000"]
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
  endpoint = ["http://kind-registry:5000"]
EOF'

    # Restart containerd to apply the configuration
    echo " -> Restarting containerd..."
    docker exec "${FULL_NODE_NAME}" systemctl restart containerd

    # Wait for containerd to be ready again
    until docker exec "${FULL_NODE_NAME}" test -S /var/run/containerd/containerd.sock; do
        sleep 1
    done
    sleep 1

    # 4. Join the node to the cluster
    echo " -> Joining node to the Kubernetes cluster..."
    # Appended --ignore-preflight-errors=all to bypass swap/system warnings
    docker exec "${FULL_NODE_NAME}" ${JOIN_CMD} --ignore-preflight-errors=all >/dev/null

    # 5. Wait for node to be ready if requested
    if [[ "$WAIT_READY" == true ]]; then
        echo " -> Waiting for node to become Ready..."
        TIMEOUT=300 # 5 minutes timeout
        ELAPSED=0
        while [[ $ELAPSED -lt $TIMEOUT ]]; do
            # Use kubectl with proper context and simpler jsonpath
            if kubectl get node "${FULL_NODE_NAME}" &>/dev/null; then
                NODE_STATUS=$(kubectl get node "${FULL_NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
                if [[ "$NODE_STATUS" == "True" ]]; then
                    echo "✅ Node '${FULL_NODE_NAME}' is Ready!"
                    break
                fi
            fi
            sleep 2
            ELAPSED=$((ELAPSED + 2))
        done

        if [[ $ELAPSED -ge $TIMEOUT ]]; then
            NODE_STATUS=$(kubectl get node "${FULL_NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            echo "⚠️  Warning: Node '${FULL_NODE_NAME}' did not become Ready within ${TIMEOUT}s"
            echo "   Current status: ${NODE_STATUS}"
            echo "   Run 'kubectl get nodes' to check its status."
        fi
    else
        echo "✅ Node '${FULL_NODE_NAME}' successfully added! Run 'kubectl get nodes' to check its status."
    fi

elif [[ "$ACTION" == "remove" ]]; then
    FULL_NODE_NAME="${CLUSTER_NAME}-${NODE_NAME}"
    echo "Removing node '${NODE_NAME}' from cluster '${CLUSTER_NAME}'..."

    # Check if node exists in Kubernetes
    if kubectl get node "${FULL_NODE_NAME}" &>/dev/null; then
        # 1. Drain the node safely
        echo " -> Draining node..."
        kubectl drain "${FULL_NODE_NAME}" --ignore-daemonsets --delete-emptydir-data --force

        # 2. Delete the node from the cluster
        echo " -> Deleting node from Kubernetes..."
        kubectl delete node "${FULL_NODE_NAME}"
    else
        echo " -> Node not found in Kubernetes (skipping k8s cleanup)"
    fi

    # 3. Remove the Docker container (always attempt this)
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${FULL_NODE_NAME}$"; then
        echo " -> Destroying Docker container..."
        docker rm -f "${FULL_NODE_NAME}" >/dev/null
    else
        echo " -> Docker container '${FULL_NODE_NAME}' not found"
        exit 1
    fi

    echo "✅ Node '${FULL_NODE_NAME}' successfully removed!"

elif [[ "$ACTION" == "clean" ]]; then
    echo "Cleaning up all kind-scale nodes..."

    # Find all containers with the kind-scale label
    if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "kind" ]] || [[ "$CLUSTER_NAME" == "kind" && $# -gt 1 ]]; then
        # Filter by specific cluster if provided
        echo " -> Searching for nodes in cluster '${CLUSTER_NAME}'..."
        CONTAINERS=$(docker ps -a --filter "label=${KIND_SCALE_LABEL}" --filter "label=io.kindscale.cluster=${CLUSTER_NAME}" --format '{{.Names}}')
    else
        # Clean all kind-scale nodes from all clusters
        echo " -> Searching for all kind-scale nodes across all clusters..."
        CONTAINERS=$(docker ps -a --filter "label=${KIND_SCALE_LABEL}" --format '{{.Names}}')
    fi

    if [[ -z "$CONTAINERS" ]]; then
        echo " -> No kind-scale nodes found."
        exit 0
    fi

    echo " -> Found $(echo "$CONTAINERS" | wc -l | tr -d ' ') node(s) to clean:"
    echo "$CONTAINERS" | sed 's/^/    - /'

    # For each container, try to drain and delete from k8s first
    for CONTAINER in $CONTAINERS; do
        echo ""
        echo " -> Processing ${CONTAINER}..."

        # Get the cluster name from the container label
        CONTAINER_CLUSTER=$(docker inspect "${CONTAINER}" --format '{{index .Config.Labels "io.kindscale.cluster"}}' 2>/dev/null)

        if [[ -n "$CONTAINER_CLUSTER" ]]; then
            # Set KUBECONFIG to the correct cluster
            CONTAINER_KUBECONFIG="$HOME/liqo-kubeconf-${CONTAINER_CLUSTER}"

            # Try to drain and delete from Kubernetes (may fail if cluster is down)
            if [[ -f "$CONTAINER_KUBECONFIG" ]]; then
                if KUBECONFIG="$CONTAINER_KUBECONFIG" kubectl get node "${CONTAINER}" &>/dev/null; then
                    echo "    - Draining from Kubernetes..."
                    KUBECONFIG="$CONTAINER_KUBECONFIG" kubectl drain "${CONTAINER}" --ignore-daemonsets --delete-emptydir-data --force --timeout=30s 2>/dev/null || echo "    - Warning: Could not drain node (cluster may be down)"

                    echo "    - Deleting from Kubernetes..."
                    KUBECONFIG="$CONTAINER_KUBECONFIG" kubectl delete node "${CONTAINER}" --timeout=30s 2>/dev/null || echo "    - Warning: Could not delete node from Kubernetes"
                else
                    echo "    - Node not found in Kubernetes (skipping k8s cleanup)"
                fi
            else
                echo "    - Kubeconfig not found for cluster '${CONTAINER_CLUSTER}' (skipping k8s cleanup)"
            fi
        else
            echo "    - Could not determine cluster (skipping k8s cleanup)"
        fi

        # Remove the Docker container
        echo "    - Removing Docker container..."
        docker rm -f "${CONTAINER}" >/dev/null
        echo "    ✓ ${CONTAINER} removed"
    done

    echo ""
    echo "✅ Cleanup complete!"

else
    echo "Error: Invalid action '${ACTION}'."
    usage
fi
