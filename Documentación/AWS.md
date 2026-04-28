# Arquitectura de Red AWS: Proyecto "Estadio"


## 1. Recinto Físico: VPC (`10.0.0.0/16`)
Toda la infraestructura reside dentro de una única VPC. A nivel conceptual, este es el muro exterior del estadio.


Se ha reservado un bloque CIDR amplio (`10.0.0.0/16`), proporcionando más de 65.000 direcciones IP privadas para evitar conflictos de direccionamiento a futuro. Por diseño de la arquitectura, ningún recurso en este bloque tiene acceso a Internet por defecto.


Para enlazar esta red con el exterior, Terraform aprovisionó un **Internet Gateway (IGW)**, que actúa como el enlace físico de fibra óptica entre la VPC y la infraestructura de borde de Amazon.


---


## 2. Subred Pública y Firewall
Inmediatamente detrás del IGW se encuentra la subred pública. Esta red aloja un único recurso crítico: el **Firewall (nodo Bastión)**.


Esta instancia asume tres roles fundamentales en la topología:
* **Punto de entrada (AWS):** Es la única máquina aprovisionada con una IP Elástica (pública y estática). Constituye el único vector de acceso autorizado por SSH desde el exterior.
* **Router interno:** Se ha deshabilitado explícitamente el atributo `source_dest_check` en su interfaz de red (ENI) en la consola de AWS. Esto le autoriza a recibir y enrutar paquetes cuyo origen o destino final no es la propia máquina.
* **NAT Gateway:** Mediante la configuración de `iptables` (`MASQUERADE`), intercepta el tráfico saliente de las máquinas internas, enmascara sus IPs privadas y lo encamina hacia Internet utilizando su propia IP pública.


---


## 3.Subredes Privadas
Detrás del Firewall operan tres subredes estrictamente privadas. Ninguna instancia aquí posee IP pública; todo el tráfico de salida a Internet y las conexiones de administración están forzados a transitar a través del Firewall.


### Subred Visitantes (`10.0.3.0/24`)
Zona de acceso aislada para los usuarios finales (espectadores).
* **Visitantes-Web-Estadio (`t2.micro`):** Servidor encargado de despachar el reproductor de vídeo HLS a los clientes.
* **Portal Cautivo:** Entorno que simula el *landing page* o página de inicio de sesión de la red WiFi del recinto.
* **iPerf:** Nodo de pruebas utilizado para la inyección masiva de tráfico y *benchmarking* del rendimiento de red.


### Subred Gestión (`10.0.4.0/24`)
El *backend* de procesamiento y distribución de contenido.
* **Balanceador:** Nodo proxy que recibe las peticiones de los visitantes y distribuye la carga operativa.
* **Nodos HLS 1 y 2:** Instancias ejecutando contenedores Docker con `Nginx-RTMP`. Su función es la ingesta, procesamiento y empaquetado del flujo de vídeo en directo.


### Subred SOC (`10.0.6.0/24`)
El Centro de Operaciones de Seguridad. Entorno fortificado y altamente restringido.
* **SOC Core Docker (`t3.large`):** El nodo de mayor capacidad de cómputo de la red. Aloja el stack completo de monitorización e incidentes: **Wazuh, TheHive y Prometheus**.
* *Estrategia de almacenamiento:* Se aprovisionó con doble disco. Además del volumen raíz para el sistema operativo, cuenta con un volumen EBS `gp3` dedicado de 50GB. Esto garantiza la persistencia, el rendimiento y el aislamiento de los logs y bases de datos ante posibles fallos de la instancia.


---


## 4. Defensa: Capa de Enrutamiento y Seguridad
La política de control de acceso se implementa mediante un modelo de seguridad en dos capas para evitar un punto único de fallo:


1. **Nivel de Infraestructura (Security Groups de AWS):**
  Actúan de forma aislada en la interfaz de cada instancia. El `sg_firewall` autoriza la entrada SSH desde Internet, mientras que el `sg_servicios` permite la comunicación lateral entre los nodos internos.


2. **Nivel de Sistema Operativo (Iptables en el Firewall):**
  Aunque los Security Groups permiten que la red interna se comunique, el salto de red entre subredes cruzadas (ej. de Visitantes a SOC) pasa físicamente por el Firewall. Aquí es donde aplican las políticas de control de red vía `iptables`.
  * *Ejemplo de ACL:* Se autoriza a la subred Visitantes a consultar el puerto TCP/8000 en la subred Gestión, pero todo el tráfico originado en Visitantes con destino a la subred SOC se encuentra bloqueado (DROP) al 100%.
