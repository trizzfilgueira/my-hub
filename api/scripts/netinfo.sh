#!/bin/bash
# Informações de rede — lê /host/proc (sem nsenter)

# IP público
PUB_IP=$(curl -sf --max-time 5 https://ifconfig.me 2>/dev/null || \
         curl -sf --max-time 5 https://api4.my-ip.io/ip 2>/dev/null || \
         echo "N/A")

# Interface principal — exclui lo, docker*, veth*, br-*, virbr*
IFACE=$(awk 'NR>2 {
    gsub(/:$/, "", $1)
    n = $1
    if (n == "lo") next
    if (n ~ /^docker/) next
    if (n ~ /^veth/) next
    if (n ~ /^br-/) next
    if (n ~ /^virbr/) next
    print n; exit
}' /host/proc/net/dev 2>/dev/null || echo "N/A")

# SSH ativo — lê via PID 1 para garantir o namespace de rede do host
SSH_ACTIVE=$(awk '$4=="0A"{split($2,a,":"); if(a[2]=="0016"){f=1}} END{if(f) print "true"; else print "false"}' \
    /host/proc/1/net/tcp /host/proc/1/net/tcp6 2>/dev/null || echo "false")

# Firewall — verifica iptables (IPv4 e IPv6)
FIREWALL="inativo"
if grep -q "filter" /host/proc/net/ip_tables_names 2>/dev/null; then
    FIREWALL="ativo"
elif grep -q "filter" /host/proc/net/ip6_tables_names 2>/dev/null; then
    FIREWALL="ativo"
elif [ -f /host/proc/net/netfilter/nf_conntrack_count ] 2>/dev/null; then
    FIREWALL="ativo"
fi

# Fail2ban — procura processo no /host/proc
FAIL2BAN="inativo"
for f in /host/proc/[0-9]*/comm; do
    if [ -r "$f" ] && grep -q "fail2ban" "$f" 2>/dev/null; then
        FAIL2BAN="ativo"
        break
    fi
done

echo "PUB_IP=$PUB_IP"
echo "IFACE=$IFACE"
echo "SSH_ACTIVE=$SSH_ACTIVE"
echo "FIREWALL=$FIREWALL"
echo "FAIL2BAN=$FAIL2BAN"
