#!/usr/bin/env bash

function get_subnet() {
    local DOCKER_NETWORK="$1"
    docker network inspect $DOCKER_NETWORK | jq '.[0].IPAM.Config[0].Subnet' | tr -d '"'
}


function block_api() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -I LIQO-$CLUSTER1-$CLUSTER2 --src "$(get_subnet kind-liqo-$CLUSTER1)" --dst "$(get_subnet kind-liqo-$CLUSTER2)" -p tcp --dport 6443 -j DROP
    sudo iptables -I LIQO-$CLUSTER2-$CLUSTER1 --src "$(get_subnet kind-liqo-$CLUSTER2)" --dst "$(get_subnet kind-liqo-$CLUSTER1)" -p tcp --dport 6443 -j DROP
}

function allow_api() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -D LIQO-$CLUSTER1-$CLUSTER2 --src "$(get_subnet kind-liqo-$CLUSTER1)" --dst "$(get_subnet kind-liqo-$CLUSTER2)" -p tcp --dport 6443 -j DROP
    sudo iptables -D LIQO-$CLUSTER2-$CLUSTER1 --src "$(get_subnet kind-liqo-$CLUSTER2)" --dst "$(get_subnet kind-liqo-$CLUSTER1)" -p tcp --dport 6443 -j DROP
}

function block_gateway() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -I LIQO-$CLUSTER1-$CLUSTER2 --src "$(get_subnet kind-liqo-$CLUSTER1)" --dst "$(get_subnet kind-liqo-$CLUSTER2)" -p udp --dport 5871 -j DROP
    sudo iptables -I LIQO-$CLUSTER2-$CLUSTER1 --src "$(get_subnet kind-liqo-$CLUSTER2)" --dst "$(get_subnet kind-liqo-$CLUSTER1)" -p udp --dport 5871 -j DROP
}

function allow_gateway() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -D LIQO-$CLUSTER1-$CLUSTER2 --src "$(get_subnet kind-liqo-$CLUSTER1)" --dst "$(get_subnet kind-liqo-$CLUSTER2)" -p udp --dport 5871 -j DROP
    sudo iptables -D LIQO-$CLUSTER2-$CLUSTER1 --src "$(get_subnet kind-liqo-$CLUSTER2)" --dst "$(get_subnet kind-liqo-$CLUSTER1)" -p udp --dport 5871 -j DROP
}

function block_auth() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -I LIQO-$CLUSTER1-$CLUSTER2 --src "$(get_subnet kind-liqo-$CLUSTER1)" --dst "$(get_subnet kind-liqo-$CLUSTER2)" -p tcp --dport 443 -j DROP
    sudo iptables -I LIQO-$CLUSTER2-$CLUSTER1 --src "$(get_subnet kind-liqo-$CLUSTER2)" --dst "$(get_subnet kind-liqo-$CLUSTER1)" -p tcp --dport 443 -j DROP
}

function allow_auth() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -D LIQO-$CLUSTER1-$CLUSTER2 --src "$(get_subnet kind-liqo-$CLUSTER1)" --dst "$(get_subnet kind-liqo-$CLUSTER2)" -p tcp --dport 443 -j DROP
    sudo iptables -D LIQO-$CLUSTER2-$CLUSTER1 --src "$(get_subnet kind-liqo-$CLUSTER2)" --dst "$(get_subnet kind-liqo-$CLUSTER1)" -p tcp --dport 443 -j DROP
}

function block_all() {
    sudo iptables -I FORWARD -j DOCKER-KIND-LIQO-TRAFFIC
}

function allow_all() {
    local CLUSTER1="$1"
    local CLUSTER2="$2"

    sudo iptables -D FORWARD -j DOCKER-KIND-LIQO-TRAFFIC
    # Delete also possible rules previuosly created
    allow_api $CLUSTER1 $CLUSTER2
    allow_gateway $CLUSTER1 $CLUSTER2
    allow_auth $CLUSTER1 $CLUSTER2
    
}