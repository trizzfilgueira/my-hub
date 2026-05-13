#!/bin/bash
# Verificação de segurança — roda dentro do container (pid:host + privileged)
# Usa /host/proc para leituras e nsenter para comandos no host

NSE="nsenter -t 1 -m -u -i -n --"

# Executa apt-get -s upgrade uma única vez e reutiliza a saída
APT_OUT=$(${NSE} apt-get -s upgrade 2>/dev/null || echo "")

UPDATES=$(echo "$APT_OUT" | grep -P '^\d+ upgraded' | awk '{print $1}' | tr -d '\n\r')
[ -z "$UPDATES" ] && UPDATES="0"

SECURITY=$(echo "$APT_OUT" | grep -ci "security.*Inst\|Inst.*security" 2>/dev/null || echo "0")
[ -z "$SECURITY" ] && SECURITY="0"

# Reboot necessário (arquivo no host)
REBOOT=$(${NSE} test -f /var/run/reboot-required 2>/dev/null && echo "true" || echo "false")

# SSH ativo — lê via PID 1 para garantir o namespace de rede do host
SSH_ACTIVE=$(awk '$4=="0A"{split($2,a,":"); if(a[2]=="0016"){f=1}} END{if(f) print "active"; else print "inactive"}' \
    /host/proc/1/net/tcp /host/proc/1/net/tcp6 2>/dev/null || echo "inactive")

echo "UPDATES=$UPDATES"
echo "SECURITY=$SECURITY"
echo "REBOOT=$REBOOT"
echo "SSH=$SSH_ACTIVE"
