Comenzamos chicos

Aqui en un futuro deberá haber un indice indexado a cada uno de los puntos

# Proyecto: Infraestructura Tecnológica para Recintos de Gran Aforo

## 1. Justificación y Objetivos del Proyecto
Inspirados en los recientes despliegues tecnológicos de recintos masivos, este proyecto plantea el diseño, despliegue y fortificación de la infraestructura necesaria para dar soporte al **anillo WiFi** y los **servicios de streaming interno** de un recinto de gran aforo (simulando el *Palau Sant Jordi*).

El objetivo principal es demostrar la convergencia de cuatro disciplinas clave del ciclo **ASIR**:

* **Redes y Enrutamiento:** Diseño de topología en la nube y control de acceso perimetral.
* **Sistemas y Alta Disponibilidad:** Contenedorización de servicios y balanceo de carga.
* **Ciberseguridad (Blue Team):** Implementación de un CiberSOC, recolección de eventos y respuesta activa (*Active Response*).
* **Monitorización:** Telemetría en tiempo real del rendimiento de los sistemas.

---

## 2. Topología y Arquitectura Cloud (AWS VPC)
El entorno físico se emulará utilizando **Amazon Web Services (AWS)** bajo la capa de uso gratuito, desplegando una **Virtual Private Cloud (VPC)** segmentada para aislar los recursos públicos de los privados.

* **VPC Principal (`10.0.0.0/16`):** Contendrá todas las subredes del proyecto.
* **Subred Pública (`10.0.1.0/24`):** Conectada a un Internet Gateway (IGW). Aquí residirá la interfaz WAN del firewall perimetral.
* **Subred Privada de Servicios (`10.0.2.0/24`):** Aislada de internet directamente. Aloja los servidores de streaming y el balanceador de carga (salida a internet vía NAT).
* **Subred de Gestión / SOC (`10.0.3.0/24`):** Red aislada para herramientas de monitorización y el SIEM.

---

## 3. Desglose Técnico de los Nodos
El proyecto consta de **5 instancias EC2** (tipo t2.micro/t3.micro Linux) y servicios desplegados mediante **Docker**.

### Nodo 1: Firewall Perimetral y Control de Acceso
* **Tecnología:** pfSense (AMI nativa o sobre FreeBSD).
* **Rol:** NAT Gateway e inspección de tráfico.
* **Portal Cautivo:** Configurado en la interfaz LAN para simular el WiFi del estadio (*"Palau_Guest_WiFi"*). Obligará a la aceptación de términos antes de permitir el acceso a la red de servicios.

### Nodo 2: Balanceador de Carga / Reverse Proxy
* **Tecnología:** Nginx.
* **Rol:** Punto de entrada único para peticiones de vídeo. Distribuye el tráfico HTTP (Capa 7) mediante algoritmos *Round-Robin* o *Least Connections*.

### Nodos 3 y 4: Clúster de Streaming HLS
* **Tecnología:** Docker Compose + `tiangolo/nginx-rtmp`.
* **Rol:** Procesamiento de vídeo. Reciben flujo RTMP (puerto 1935) y lo transcodifican a fragmentos `.m3u8` y `.ts` (**HLS**) para consumo de los clientes.

### Nodo 5: CiberSOC y Telemetría
Contiene el stack de seguridad y monitorización en contenedores:
1.  **Wazuh Manager (SIEM):** Centralización de logs y telemetría de todos los nodos.
2.  **Prometheus & Grafana:** Extracción de métricas (CPU, peticiones concurrentes) y renderizado en dashboards en tiempo real.
3.  **Honeypot Cowrie:** Simulación de servicio SSH (puerto 22) para registrar ataques de fuerza bruta.

---

## 4. Flujo de Integración y Respuesta Activa
Se automatiza la seguridad mediante un flujo de **Active Response** entre Wazuh y pfSense:

1.  **Detección:** Un atacante realiza fuerza bruta contra el Honeypot Cowrie.
2.  **Recolección:** El agente local envía los logs JSON al **Wazuh Manager**.
3.  **Correlación:** El SIEM detecta una intrusión crítica (Nivel 10+).
4.  **Respuesta Activa:** Wazuh ejecuta un script que se comunica vía API/SSH con el **pfSense**.
5.  **Mitigación:** pfSense añade la IP a una tabla de bloqueo (`DROP`), expulsando al atacante instantáneamente.

---

## 5. Pruebas de Carga y Simulación
Para validar el sistema, se ejecutarán dos vectores simultáneos:

* **Carga Legítima (Estrés):** Uso de *Apache JMeter* o *K6* para simular miles de peticiones HLS. Se verificará en Grafana el reparto equitativo entre los nodos de streaming.
* **Carga Maliciosa (Ataque):** Uso de *Kali Linux* para lanzar ataques **Slowloris** (DoS) y fuerza bruta, demostrando que la infraestructura bloquea al atacante sin interrumpir el servicio a los usuarios legítimos.
