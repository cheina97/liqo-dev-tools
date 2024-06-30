#!/usr/bin/env bash

export AWS_REGION=eu-west-1
CLUSTER_NUMBER=3

CREATE_CLUSTERS=false
INSTALL_KYVERNO=false
INSTALL_LBCONTROLLER=true
INSTALL_LIQO=false

createcluster() {
    local CLUSTER_NAME=$1
    eksctl create cluster --name "${CLUSTER_NAME}" --version=1.28 --managed --spot --instance-types=c5.large --region="${AWS_REGION}" --kubeconfig "$HOME/liqo-kubeconf-${CLUSTER_NAME}"
}

install_lbcontroller() {
    local CLUSTER_NAME=$1
    echo "Installing AWS Load Balancer Controller on cluster ${CLUSTER_NAME}"
    eksctl utils associate-iam-oidc-provider --region "${AWS_REGION}" --cluster "${CLUSTER_NAME}" --approve
    #curl -o "${HOME}/iam-policy.json" https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
    #aws iam create-policy \
    #--policy-name AWSLoadBalancerControllerIAMPolicy \
    #--policy-document "file://${HOME}/iam-policy.json"

    eksctl create iamserviceaccount \
        --cluster="${CLUSTER_NAME}" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=arn:aws:iam::098800332668:policy/AWSLoadBalancerControllerIAMPolicy \
        --override-existing-serviceaccounts \
        --region "${AWS_REGION}" \
        --approve

    helm repo add eks https://aws.github.io/eks-charts
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system --set clusterName="${CLUSTER_NAME}" \
        --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller \
        --set enableServiceMutatorWebhook=false \
        --kubeconfig "$HOME/liqo-kubeconf-${CLUSTER_NAME}"
}

function install_kyverno() {
    local CLUSTER_NAME="$1"
    local KUBECONFIG="$HOME/liqo-kubeconf-${CLUSTER_NAME}"
    helm install kyverno kyverno/kyverno -n kyverno --create-namespace --kubeconfig "${KUBECONFIG}"
}

function install_liqo() {
    local CLUSTER_NAME="$1"
    LIQO_VERSION="ee1617914bd5cfdc090504c68b386de949b23da9"
    KUBECONFIG="$HOME/liqo-kubeconf-${CLUSTER_NAME}"

    liqoctl install eks --eks-cluster-name "${CLUSTER_NAME}" --eks-cluster-region "${AWS_REGION}" \
        --kubeconfig "${KUBECONFIG}" \
        --user-name liqo-user-cheina-aruba \
        --local-chart-path "${HOME}/Documents/liqo/liqo/deployments/liqo" \
        --version ${LIQO_VERSION} \
        --cluster-labels="cl.liqo.io/kubeconfig=liqo-kubeconf-${CLUSTER_NAME}"
}

if [ "$CREATE_CLUSTERS" = true ]; then
    PIDS=()
    for i in $(seq 1 $CLUSTER_NUMBER); do
        createcluster "eks${i}" &
        PIDS+=($!)
    done

    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi

if [ "$INSTALL_KYVERNO" = true ]; then
    PIDS=()
    for i in $(seq 1 $CLUSTER_NUMBER); do
        install_kyverno "eks${i}" &
        PIDS+=($!)
    done

    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi

if [ "$INSTALL_LBCONTROLLER" = true ]; then
    PIDS=()
    for i in $(seq 1 $CLUSTER_NUMBER); do
        install_lbcontroller "eks${i}" &
        PIDS+=($!)
    done

    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi

if [ "$INSTALL_LIQO" = true ]; then
    PIDS=()
    for i in $(seq 1 $CLUSTER_NUMBER); do
        install_liqo "eks${i}" &
        PIDS+=($!)
    done

    for PID in "${PIDS[@]}"; do
        wait "$PID"
    done
fi


echo
tput setaf 2
tput bold
echo "STARTED SUCCESSFULLY"
tput sgr0
echo

# liqoctl peer in-band --kubeconfig "$HOME/liqo-kubeconf-eks1" --remote-kubeconfig "$HOME/liqo-kubeconf-eks2" --bidirectional
