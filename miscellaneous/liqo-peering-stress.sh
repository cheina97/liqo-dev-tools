#!/usr/bin/env bash

set -e 
set -u

on_error(){
  noti -k -t "Liqo Peering Stress :fire:" -m "Cheina peering stress test failed"
}
 
trap 'on_error' ERR

n_loops=$(($1-1))

noti -k -t "Liqo Peering Stress :fire:" -m "Cheina started peering stress test: ${n_loops} loops"

export KUBECONFIG=$HOME/liqo_kubeconf_cheina-cluster2

PEERCMD=$(liqoctl generate peer-command --only-command)

export KUBECONFIG=$HOME/liqo_kubeconf_cheina-cluster1

eval "${PEERCMD}"
sleep 5s

for((i=0;i<n_loops;i++)); do
    liqoctl unpeer out-of-band  cheina-cluster2 --skip-confirm
    sleep 5s
    if [ $((i%10)) -eq 0 ] && [ $i -ne 0 ]; then
        noti -k -t "Liqo Peering Stress :fire:" -m "Cheina peering stress test: reached ${i} loops" 
    fi
    eval "${PEERCMD}"
    sleep 5s
done

liqoctl unpeer out-of-band  cheina-cluster2 --skip-confirm

noti -k -t "Liqo Peering Stress :fire:" -m "Cheina finished peering stress test: ${n_loops} loops"

echo "$(tput setaf 2)"Finished"$(tput sgr0)"

