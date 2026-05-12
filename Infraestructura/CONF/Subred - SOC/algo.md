# Script de Reseteo e Instalación Limpia de Wazuh Agent

```bash
#!/bin/bash

# ================= CONFIGURACIÓN =================
MANAGER_IP="10.0.6.148"
API_USER="admin"          # Usuario por defecto de Wazuh
API_PASS="admin"          # Poner la contraseña del Dashboard
# =================================================

AGENT_NAME=$1
AGENT_GROUP=$2

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Uso: sudo bash soc_reset.sh NOMBRE_NUEVO GRUPO"
    exit 1
fi

echo "--- 1. SOLICITANDO TOKEN A LA API DEL MANAGER ---"
# Obtenemos el token para poder operar
TOKEN=$(curl -u "$API_USER:$API_PASS" -k -X POST "https://$MANAGER_IP:55000/security/auth/get?run_as=admin" | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "ERROR: No se pudo conectar con la API. Revisa tu contraseña o IP."
    exit 1
fi

echo "--- 2. BUSCANDO Y ELIMINANDO REGISTRO ANTIGUO ($AGENT_NAME) ---"
# Buscamos el ID del agente que tenga ese nombre para borrarlo
AGENT_ID=$(curl -k -X GET "https://$MANAGER_IP:55000/agents?name=$AGENT_NAME" -H "Authorization: Bearer $TOKEN" | grep -oP '"id":"\K[0-9]+')

if [ ! -z "$AGENT_ID" ]; then
    echo "Agente encontrado con ID: $AGENT_ID. Eliminando..."
    curl -k -X DELETE "https://$MANAGER_IP:55000/agents?agent_list=$AGENT_ID&status=all" -H "Authorization: Bearer $TOKEN"
else
    echo "No había registros previos con el nombre $AGENT_NAME. Seguimos."
fi

echo "--- 3. EXTERMINIO DE LA INSTALACIÓN LOCAL ---"
sudo systemctl stop wazuh-agent 2>/dev/null
sudo rm -f /var/lib/dpkg/info/wazuh-agent.*
sudo dpkg --remove --force-remove-reinstreq wazuh-agent 2>/dev/null
sudo apt-get purge wazuh-agent -y 2>/dev/null
sudo rm -rf /var/ossec
sudo rm -rf /etc/wazuh-agent
sudo systemctl daemon-reload

echo "--- 4. RE-INSTALACIÓN LIMPIA ---"
if [ ! -f wazuh-agent_4.9.0-1_amd64.deb ]; then
    wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.9.0-1_amd64.deb
fi

sudo WAZUH_MANAGER="$MANAGER_IP" \
     WAZUH_AGENT_NAME="$AGENT_NAME" \
     WAZUH_AGENT_GROUP="$AGENT_GROUP" \
     dpkg -i wazuh-agent_4.9.0-1_amd64.deb

echo "--- 5. ARRANCANDO ---"
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent

echo "¡PROCESO COMPLETADO! Revisa tu Dashboard en 30 segundos."
```

## Uso
```bash
sudo chmod +x soc_reset.sh
```

```bash
sudo bash soc_reset.sh NOMBRE_NUEVO GRUPO
```

## Ejemplo

```bash
sudo bash soc_reset.sh servidor-web linux
```

## Qué hace este script

1. Solicita un token a la API de Wazuh.
2. Busca y elimina agentes antiguos con el mismo nombre.
3. Borra completamente la instalación local del agente.
4. Descarga e instala una copia limpia del agente Wazuh.
5. Arranca y habilita el servicio automáticamente.
