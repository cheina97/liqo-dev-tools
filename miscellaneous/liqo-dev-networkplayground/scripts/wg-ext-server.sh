#!/usr/bin/env bash

umask 077
wg genkey > privatekey-ext
wg pubkey < privatekey-ext > publickey-ext

ip link add dev wg-ext type wireguard
ip address add dev wg-ext 20.1.0.1/24
wg set wg-ext listen-port 51820 private-key ./privatekey-ext peer PUBKEY allowed-ips 0.0.0.0/0
ip link set up dev wg-ext

sysctl -w net.ipv4.ip_forward=1
ip route add 10.122.0.0/16 dev wg-ext
ip route add 20.1.0.2/32 dev wg-ext
iptables -F

iptables -A FORWARD -o eth0 -i wg-ext -j ACCEPT
iptables -A FORWARD -i eth0 -o wg-ext -j ACCEPT
iptables -A INPUT -i eth0 -j ACCEPT
iptables -A INPUT -i wg-ext -j ACCEPT
iptables -A OUTPUT -o eth0 -j ACCEPT
iptables -A OUTPUT -o wg-ext -j ACCEPT
