# 🛡️ Guía de Administración: Gestión de Agentes Wazuh

Esta documentación detalla los procedimientos para la resolución de conflictos de identidad, limpieza profunda de nodos y automatización del despliegue en el entorno Wazuh SOC.

---

# 1. Arquitectura de Identidad

Wazuh identifica a los agentes mediante un sistema de llaves únicas (`client.keys`).

Si el Manager es reinstalado o sus volúmenes son borrados, los agentes pierden la confianza y deben ser "exterminados" localmente y eliminados del Manager para permitir un nuevo apretón de manos (*handshake*).

---

# 2. Herramientas de Gestión en el Manager

El "cerebro" reside en el contenedor:

```bash
single-node-wazuh.manager-1
```

## Listado y Borrado Manual

### Listar agentes registrados

```bash
sudo docker exec -it single-node-wazuh.manager-1 /var/ossec/bin/manage_agents -l
```

### Eliminar registro por ID

```bash
sudo docker exec -it single-node-wazuh.manager-1 /var/ossec/bin/manage_agents -r [ID]
```

---

# 3. Scripts de Automatización Implementados

## A. Script de Limpieza Interactiva (`borrar_agente.sh`)

### Uso

Permite limpiar el Dashboard desde la consola del servidor SOC sin recordar comandos largos de Docker.

### Código

```bash
#!/bin/bash

CONTENEDOR="single-node-wazuh.manager-1"

sudo docker exec -it $CONTENEDOR /var/ossec/bin/manage_agents -l

read -p "ID del agente a BORRAR: " AGENT_ID

sudo docker exec -it $CONTENEDOR /var/ossec/bin/manage_agents -r $AGENT_ID
```

---

## B. Script Maestro de Re-enrolamiento (`soc_reset.sh`)

### Uso

Se ejecuta en el Agente (Nginx, Web, etc.).

Realiza una limpieza "nuclear" y vuelve a registrar el agente automáticamente.

### Acciones realizadas

- Llama a la API (`55000/TCP`) para borrar el ID antiguo.
- Fuerza la eliminación de paquetes `dpkg` corruptos.
- Borra físicamente `/var/ossec` para eliminar llaves antiguas.
- Reinstala el agente y lo asigna al Manager `10.0.6.148`.
- Configura el Nombre y Grupo indicados en la ejecución.

---

# 4. Resolución de Errores Comunes

## Error: `Duplicate agent name` o `Connection Refused`

### Causa

El agente intenta conectar con una llave antigua o el nombre ya existe en la base de datos del Manager.

### Solución

1. Borrar el ID en el Manager:

```bash
manage_agents -r
```

2. Borrar la llave local del agente:

```bash
/var/ossec/etc/client.keys
```

3. Reiniciar el servicio:

```bash
sudo systemctl restart wazuh-agent
```

---

## Error: `dpkg: error processing package wazuh-agent`

### Causa

El script de pre-remoción falla porque el servicio está bloqueado o corrupto.

### Solución — "El Exterminio"

```bash
sudo rm -f /var/lib/dpkg/info/wazuh-agent.*

sudo dpkg --remove --force-remove-reinstreq wazuh-agent

sudo rm -rf /var/ossec
```

---

# 5. Clasificación de Grupos y Logs

Se han definido tres perfiles de configuración centralizada en el Manager.

| Grupo      | Objetivo                        | Logs Monitorizados |
|------------|--------------------------------|--------------------|
| Visitantes | Servidores Web (Nginx)         | `/var/log/nginx/access.log`, `/var/log/auth.log` |
| Gestion    | HLS, Balanceadores y BBDD      | `/var/log/syslog`, `/var/log/icecast2/error.log` |
| DMZ        | Servidores expuestos           | Reglas de hardening y logs de sistema |

---

# 6. Mantenimiento Preventivo

## Verificación de logs del Manager

```bash
sudo docker logs single-node-wazuh.manager-1 --tail 100
```

## Estado de puertos

Asegurar que los siguientes puertos estén abiertos en el **Security Group** o Firewall del Manager:

| Puerto | Protocolo | Uso |
|---------|------------|-----|
| 1514    | TCP        | Recepción de eventos de agentes |
| 1515    | TCP        | Registro de agentes |
| 55000   | TCP        | API de Wazuh |

---

# Información del Documento

- **Fecha de generación:** 12 de Mayo de 2026
- **Estado del sistema:** Operacional
- **Situación actual:** Agentes migrando a nombres descriptivos
