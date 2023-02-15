#!/usr/bin/env bash

# TO ENABLE TRAFFIC BETWEEN ALL KIND CLUSTERS:
# sudo iptables -I FORWARD -j DOCKER-KIND-LIQO-TRAFFIC

# TO DISABLE TRAFFIC BETWEEN ALL KIND CLUSTERS
# sudo iptables -D FORWARD -j DOCKER-KIND-LIQO-TRAFFIC

# WARNING: this script is not idempotent, it will create duplicate rules if run multiple times

# sudo iptables -I LIQO-cluster1-cluster2 -p tcp --dport 6443 -j DROP
# sudo iptables -D LIQO-cluster1-cluster2 -p tcp --dport 6443 -j DROP

declare -A cidrs
keys=()

while read -r line; do
    cidr=$(docker network inspect "$line" |jq ".[].IPAM.Config"| jq ".[0].Subnet"|cut -d '"' -f 2)
    key=$(echo "$line"|cut -d "-" -f 3)
    cidrs["${key}"]="${cidr}"
    keys+=("${key}")
done < <(docker network ls|tail -n +2| tr -s " "|cut -d " " -f 2|grep kind-liqo-)

sudo iptables -N DOCKER-KIND-LIQO-TRAFFIC
sudo iptables -I FORWARD -j DOCKER-KIND-LIQO-TRAFFIC

i=0
len=${#keys[@]}
while [ $i -lt $((len-1)) ]; do
    j=$((i+1))
    while [ $j -lt "$len" ]; do
        key1="${keys[$i]}"
        key2="${keys[$j]}"
        sudo iptables -N "LIQO-${key1}-${key2}"
        sudo iptables -N "LIQO-${key2}-${key1}"
        sudo iptables -A DOCKER-KIND-LIQO-TRAFFIC -s "${cidrs[$key1]}" -d "${cidrs[$key2]}" -j "LIQO-${key1}-${key2}"
        sudo iptables -A DOCKER-KIND-LIQO-TRAFFIC -s "${cidrs[$key2]}" -d "${cidrs[$key1]}" -j "LIQO-${key2}-${key1}"
        sudo iptables -I "LIQO-${key1}-${key2}" -j ACCEPT
        sudo iptables -I "LIQO-${key2}-${key1}" -j ACCEPT
        ((j++))
    done
    ((i++))
done

