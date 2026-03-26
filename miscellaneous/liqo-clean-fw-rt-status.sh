#!/bin/bash

set -e

echo "=========================================="
echo "Liqo Clean Firewall & Route Status Script"
echo "=========================================="
echo ""

# Parse arguments
CHECK_MODE=false
for arg in "$@"; do
    if [[ "$arg" == "--check" ]]; then
        CHECK_MODE=true
        echo "Running in CHECK mode: Listing resources with 'status' field set."
        echo ""
        break
    fi
done

# Check if kubectl is available
if ! command -v kubectl &>/dev/null; then
    echo "Error: kubectl not found in PATH"
    exit 1
fi

# Check if KUBECONFIG is set or if we can connect to a cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    echo "Please ensure KUBECONFIG is set or kubectl is configured properly"
    exit 1
fi

echo "Connected to cluster: $(kubectl config current-context)"
echo ""

# Get all RouteConfiguration resources
echo "Fetching RouteConfiguration resources..."
ROUTE_CONFIGS=$(kubectl get routeconfigurations.networking.liqo.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
ROUTE_COUNT=$(echo "$ROUTE_CONFIGS" | jq '.items | length')

# Get all FirewallConfiguration resources
echo "Fetching FirewallConfiguration resources..."
FW_CONFIGS=$(kubectl get firewallconfigurations.networking.liqo.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
FW_COUNT=$(echo "$FW_CONFIGS" | jq '.items | length')

if [ "$CHECK_MODE" = true ]; then
    echo ""
    echo "=========================================="
    echo "Resources with Status field:"
    echo "=========================================="

    HAS_STATUS=false

    # Check RouteConfigurations with status
    ROUTES_WITH_STATUS=$(echo "$ROUTE_CONFIGS" | jq -r '.items[] | select(.status != null and .status != {}) | "\(.metadata.namespace)/\(.metadata.name)"')
    if [ ! -z "$ROUTES_WITH_STATUS" ]; then
        echo "RouteConfigurations:"
        echo "$ROUTES_WITH_STATUS" | sed 's/^/  - /'
        echo ""
        HAS_STATUS=true
    fi

    # Check FirewallConfigurations with status
    FWS_WITH_STATUS=$(echo "$FW_CONFIGS" | jq -r '.items[] | select(.status != null and .status != {}) | "\(.metadata.namespace)/\(.metadata.name)"')
    if [ ! -z "$FWS_WITH_STATUS" ]; then
        echo "FirewallConfigurations:"
        echo "$FWS_WITH_STATUS" | sed 's/^/  - /'
        echo ""
        HAS_STATUS=true
    fi

    if [ "$HAS_STATUS" = false ]; then
        echo "No resources found with status field set."
    fi

    exit 0
fi

echo ""
echo "=========================================="
echo "Found resources:"
echo "  - RouteConfigurations: $ROUTE_COUNT"
echo "  - FirewallConfigurations: $FW_COUNT"
echo "=========================================="
echo ""

# Display RouteConfigurations
if [ "$ROUTE_COUNT" -gt 0 ]; then
    echo "RouteConfigurations:"
    echo "$ROUTE_CONFIGS" | jq -r '.items[] | "  - \(.metadata.namespace)/\(.metadata.name)"'
    echo ""
fi

# Display FirewallConfigurations
if [ "$FW_COUNT" -gt 0 ]; then
    echo "FirewallConfigurations:"
    echo "$FW_CONFIGS" | jq -r '.items[] | "  - \(.metadata.namespace)/\(.metadata.name)"'
    echo ""
fi

# Check if there are any resources to clean
TOTAL_COUNT=$((ROUTE_COUNT + FW_COUNT))
if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo "No resources found to clean. Exiting."
    exit 0
fi

# Ask for confirmation
echo "=========================================="
echo "This will remove the status field from all $TOTAL_COUNT resources listed above."
read -p "Do you want to proceed? (yes/no): " CONFIRMATION
echo ""

if [ "$CONFIRMATION" != "yes" ]; then
    echo "Operation cancelled by user."
    exit 0
fi

echo "Starting status cleanup..."
echo ""

# Clean RouteConfiguration status
ROUTES_TO_CLEAN=$(echo "$ROUTE_CONFIGS" | jq -r '.items[] | select(.status != null and .status != {}) | "\(.metadata.namespace) \(.metadata.name)"')
if [ ! -z "$ROUTES_TO_CLEAN" ]; then
    echo "Cleaning RouteConfiguration status..."
    echo "$ROUTES_TO_CLEAN" | while read -r namespace name; do
        echo "  - Cleaning $namespace/$name"
        kubectl patch routeconfigurations.networking.liqo.io "$name" -n "$namespace" \
            --type=json \
            --subresource=status \
            -p='[{"op": "remove", "path": "/status"}]' 2>/dev/null && echo "    ✓ Patched" || echo "    ✗ Failed"
    done
    echo ""
else
    echo "No RouteConfigurations with status to clean."
    echo ""
fi

# Clean FirewallConfiguration status
FWS_TO_CLEAN=$(echo "$FW_CONFIGS" | jq -r '.items[] | select(.status != null and .status != {}) | "\(.metadata.namespace) \(.metadata.name)"')
if [ ! -z "$FWS_TO_CLEAN" ]; then
    echo "Cleaning FirewallConfiguration status..."
    echo "$FWS_TO_CLEAN" | while read -r namespace name; do
        echo "  - Cleaning $namespace/$name"
        kubectl patch firewallconfigurations.networking.liqo.io "$name" -n "$namespace" \
            --type=json \
            --subresource=status \
            -p='[{"op": "remove", "path": "/status"}]' 2>/dev/null && echo "    ✓ Patched" || echo "    ✗ Failed"
    done
    echo ""
else
    echo "No FirewallConfigurations with status to clean."
    echo ""
fi

echo "=========================================="
echo "Status cleanup completed successfully!"
echo "=========================================="
