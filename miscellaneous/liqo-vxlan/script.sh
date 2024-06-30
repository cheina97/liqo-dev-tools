# Script to setup the liqo vxlan manually
ip link add liqo.vxlan2 type vxlan id 23 dstport 8790 local POD_IP nolearning
bridge fdb append 00:00:00:00:00:00 dev liqo.vxlan2 dst POD_IP_DST
bridge fdb append VXLAN_MAC_DST dev liqo.vxlan2 dst POD_IP_DST
ip addr add 20.0.0.2 dev liqo.vxlan2
ip link set liqo.vxlan2 up
ip route add 20.0.0.3 dev liqo.vxlan2

ip addr show liqo.vxlan2
bridge fdb show dev liqo.vxlan2

ip link del liqo.vxlan2

10.42.2.101     10.42.2.100

22:16