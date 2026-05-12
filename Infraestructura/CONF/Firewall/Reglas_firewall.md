# Script de Configuración Automática IPTables

Guardar como:

```bash
firewall_restore.sh
```

---

## Código

```bash
#!/bin/bash

# =========================================================
# CONFIGURACIÓN AUTOMÁTICA DE FIREWALL IPTABLES
# =========================================================

# ---------- VARIABLES ----------
IP_PORTAL="10.0.3.51"
IP_STREAMING="10.0.3.206"
IP_WAZUH="10.0.6.148"

RED_INTERNA="10.0.0.0/16"
RED_SOC="10.0.6.0/24"

INTERFAZ_WAN="eth0"

# =========================================================

echo "[+] Activando IP Forwarding..."

sysctl -w net.ipv4.ip_forward=1

grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

echo "[+] Limpiando reglas anteriores..."

iptables -F
iptables -X

iptables -t nat -F
iptables -t nat -X

iptables -t mangle -F
iptables -t mangle -X

echo "[+] Configurando políticas por defecto..."

iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# =========================================================
# TABLA FILTER
# =========================================================

echo "[+] Configurando reglas FILTER..."

# Mantener conexiones activas
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Permitir tráfico de redes internas
iptables -A FORWARD -s 10.0.6.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.3.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.4.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.5.0/24 -j ACCEPT

# Acceso a servicios
iptables -A FORWARD -p tcp -d $IP_PORTAL --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d $IP_STREAMING --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d $IP_WAZUH --dport 443 -j ACCEPT

# =========================================================
# TABLA NAT
# =========================================================

echo "[+] Configurando reglas NAT..."

# Excepción SOC
iptables -t nat -A PREROUTING -s $RED_SOC -p tcp --dport 80 -j ACCEPT

# Evitar bucle portal -> streaming
iptables -t nat -A PREROUTING -d $IP_STREAMING -p tcp --dport 80 -j ACCEPT

# Portal cautivo interno
iptables -t nat -A PREROUTING -s $RED_INTERNA -p tcp --dport 80 \
-j DNAT --to-destination $IP_PORTAL:80

# Portal cautivo externo
iptables -t nat -A PREROUTING -i $INTERFAZ_WAN -p tcp --dport 80 \
-j DNAT --to-destination $IP_PORTAL:80

# Acceso externo Wazuh
iptables -t nat -A PREROUTING -p tcp ! -s $RED_INTERNA --dport 443 \
-j DNAT --to-destination $IP_WAZUH:443

# NAT Internet
iptables -t nat -A POSTROUTING -o $INTERFAZ_WAN -j MASQUERADE

# =========================================================
# INPUT LOCAL
# =========================================================

echo "[+] Configurando acceso local..."

# Conexiones activas
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Loopback
iptables -A INPUT -i lo -j ACCEPT

# SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Ping
iptables -A INPUT -p icmp -j ACCEPT

echo "[+] Instalando persistencia IPTables..."

apt update -y
apt install iptables-persistent -y

echo "[+] Guardando configuración..."

netfilter-persistent save
netfilter-persistent reload

echo ""
echo "=============================================="
echo "  FIREWALL CONFIGURADO CORRECTAMENTE"
echo "=============================================="

echo ""
echo "Reglas NAT:"
iptables -t nat -L -n -v

echo ""
echo "Reglas FILTER:"
iptables -L -n -v
```

---

## Uso

### 1. Dar permisos

```bash
chmod +x firewall_restore.sh
```

### 2. Ejecutar

```bash
sudo ./firewall_restore.sh
```
