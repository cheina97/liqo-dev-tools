#!/usr/bin/env bash

umask 077
wg genkey > privatekey-ext
wg pubkey < privatekey-ext > publickey-ext

ip link add dev wg-ext type wireguard
ip address add dev wg-ext 169.254.0.2/30
wg set wg-ext private-key ./privatekey-ext peer E2wAEOOJz0GgV2qNUQmrd9LP0E/ga6M7WM+rDseJQAQ= allowed-ips 0.0.0.0/0 endpoint 172.17.0.1:51820
ip link set up dev wg-ext

sysctl -w net.ipv4.ip_forward=1
ip route add 10.122.0.0/16 dev wg-ext
ip route add 20.1.0.1/32 dev wg-ext
iptables -F
