# 🔥 Guía de Configuración de Firewall y Portal Cautivo con IPTables

Esta documentación describe el proceso completo para desplegar un sistema de redirección y filtrado basado en **IPTables**, orientado a un entorno SOC con:

- Portal cautivo
- Streaming interno
- Acceso seguro a Wazuh
- NAT y redirección de tráfico
- Segmentación de redes internas

---

# 1. Objetivo de la Configuración

El script implementa:

- Redirección automática de tráfico HTTP hacia un portal cautivo.
- Acceso controlado a servicios internos.
- NAT y salida a Internet.
- Separación de redes internas y red SOC.
- Protección básica del firewall.
- Persistencia de acceso SSH para administración remota.

---

# 2. Requisitos Previos

Antes de ejecutar el script, verificar:

## Sistema Operativo

Compatible con:

- Ubuntu Server
- Debian
- Kali Linux
- Distribuciones Linux con IPTables

---

## Paquetes necesarios

Instalar IPTables si no está presente:

```bash
sudo apt update
sudo apt install iptables -y
```

---

## Habilitar el reenvío IP (IP Forwarding)

Editar:

```bash
sudo nano /etc/sysctl.conf
```

Buscar y descomentar:

```bash
net.ipv4.ip_forward=1
```

Aplicar cambios:

```bash
sudo sysctl -p
```

Verificar:

```bash
cat /proc/sys/net/ipv4/ip_forward
```

Debe devolver:

```text
1
```

---

# 3. Arquitectura de Red

## Redes utilizadas

| Red | Función |
|------|----------|
| `10.0.0.0/16` | Red interna general |
| `10.0.3.0/24` | Portal y Streaming |
| `10.0.4.0/24` | Servicios adicionales |
| `10.0.5.0/24` | Infraestructura auxiliar |
| `10.0.6.0/24` | Red SOC / Wazuh |

---

## Hosts principales

| Servicio | IP |
|-----------|----|
| Portal Cautivo | `10.0.3.51` |
| Streaming HLS | `10.0.3.206` |
| Wazuh Dashboard/API | `10.0.6.148` |

---

# 4. Crear el Script

Crear archivo:

```bash
nano firewall_restore.sh
```

Pegar el siguiente contenido:

```bash
#!/bin/bash

# --- CONFIGURACIÓN DE VARIABLES ---
IP_PORTAL="10.0.3.51"
IP_STREAMING="10.0.3.206"
IP_WAZUH="10.0.6.148"
RED_INTERNA="10.0.0.0/16"
RED_SOC="10.0.6.0/24"

echo "Iniciando restauración de reglas de iptables..."

# 1. Limpieza total de tablas anteriores
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 2. Políticas por defecto (Seguridad básica)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# --- TABLA FILTER (Reglas de paso de tráfico) ---
echo "Configurando tabla FILTER (FORWARD)..."

# Mantener conexiones ya abiertas
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Salida de subredes internas
iptables -A FORWARD -s 10.0.6.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.3.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.4.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.5.0/24 -j ACCEPT

# Acceso a servidores específicos
iptables -A FORWARD -p tcp -d $IP_PORTAL --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d $IP_WAZUH --dport 443 -j ACCEPT
iptables -A FORWARD -p tcp -d $IP_STREAMING --dport 80 -j ACCEPT

# --- TABLA NAT (Redirecciones) ---
echo "Configurando tabla NAT (Redirecciones)..."

# Excepción SOC: Salida directa a Internet
iptables -t nat -A PREROUTING -s $RED_SOC -p tcp --dport 80 -j ACCEPT

# Excepción Streaming: Evitar bucle del portal una vez aceptado
iptables -t nat -A PREROUTING -d $IP_STREAMING -p tcp --dport 80 -j ACCEPT

# Captura Interna: Redirigir red local al Portal Cautivo
iptables -t nat -A PREROUTING -s $RED_INTERNA -p tcp --dport 80 -j DNAT --to-destination $IP_PORTAL:80

# Captura Externa: Redirigir peticiones de Internet al Portal Cautivo
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination $IP_PORTAL:80

# Acceso Externo Wazuh
iptables -t nat -A PREROUTING -p tcp ! -s $RED_INTERNA --dport 443 -j DNAT --to-destination $IP_WAZUH:443

# Enmascaramiento para salida a Internet
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# --- ACCESO LOCAL AL FIREWALL (INPUT) ---

# Permitir conexiones ya establecidas
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Permitir loopback
iptables -A INPUT -i lo -j ACCEPT

# Permitir SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

echo "Reglas aplicadas con éxito."

iptables -t nat -L -n -v
```

---

# 5. Dar Permisos de Ejecución

```bash
chmod +x firewall_restore.sh
```

---

# 6. Ejecutar el Script

⚠️ IMPORTANTE: Ejecutar como root o sudo.

```bash
sudo ./firewall_restore.sh
```

---

# 7. Verificar las Reglas

## Tabla NAT

```bash
sudo iptables -t nat -L -n -v
```

---

## Tabla FILTER

```bash
sudo iptables -L -n -v
```

---

# 8. Persistencia de Reglas tras Reinicio

Instalar:

```bash
sudo apt install iptables-persistent -y
```

Guardar reglas actuales:

```bash
sudo netfilter-persistent save
```

Verificar:

```bash
sudo netfilter-persistent reload
```

---

# 9. Flujo de Funcionamiento

## Portal Cautivo

Todo tráfico HTTP es redirigido automáticamente a:

```text
10.0.3.51
```

---

## Streaming HLS

Una vez autenticado:

- El tráfico hacia `10.0.3.206`
- No vuelve al portal cautivo
- Evita bucles de redirección

---

## Acceso Wazuh

Las peticiones HTTPS externas (`443/TCP`) son redirigidas hacia:

```text
10.0.6.148
```

---

# 10. Seguridad Implementada

## Protección SSH

Se mantiene acceso remoto mediante:

```bash
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
```

---

## NAT y Masquerade

La salida a Internet se realiza mediante:

```bash
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

---

# 11. Solución de Problemas

## Sin acceso a Internet

Verificar:

```bash
ip route
```

Y comprobar:

```bash
sysctl net.ipv4.ip_forward
```

---

## IPTables vacío tras reinicio

Recargar:

```bash
sudo netfilter-persistent reload
```

---

## Bucle de Portal Cautivo

Comprobar excepción:

```bash
iptables -t nat -L PREROUTING -n -v
```

Debe existir:

```bash
-d 10.0.3.206 --dport 80 -j ACCEPT
```

---

# 12. Puertos Utilizados

| Puerto | Protocolo | Servicio |
|---------|------------|-----------|
| 22 | TCP | SSH |
| 80 | TCP | Portal cautivo / Streaming |
| 443 | TCP | Wazuh Dashboard/API |

---

# 13. Estado Final Esperado

✅ Portal cautivo operativo  
✅ Streaming accesible tras autenticación  
✅ Acceso remoto SSH funcional  
✅ NAT funcionando correctamente  
✅ Dashboard Wazuh accesible externamente  
✅ Segmentación de redes aplicada  

---

# Información del Documento

- **Fecha:** 12 de Mayo de 2026
- **Entorno:** AWS / Linux / IPTables
- **Estado:** Operacional
