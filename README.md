Comenzamos chicos

Aqui en un futuro deberá haber un indice indexado a cada uno de los puntos

**1. Justificación y Objetivos del Proyecto
Inspirados en los recientes despliegues tecnológicos de recintos masivos, este proyecto plantea el diseño, despliegue y fortificación de la infraestructura tecnológica necesaria para dar soporte al anillo WiFi y los servicios de streaming interno de un recinto de gran aforo (simulando el Palau Sant Jordi).
El objetivo principal es demostrar la convergencia de cuatro disciplinas clave del ciclo ASIR:
Redes y Enrutamiento: Diseño de topología en la nube y control de acceso perimetral.
Sistemas y Alta Disponibilidad: Contenedorización de servicios y balanceo de carga.
Ciberseguridad (Blue Team): Implementación de un CiberSOC, recolección de eventos y respuesta activa (Active Response).
Monitorización: Telemetría en tiempo real del rendimiento de los sistemas.
2. Topología y Arquitectura Cloud (AWS VPC)
El entorno físico se emulará utilizando Amazon Web Services (AWS) bajo la capa de uso gratuito, desplegando una Virtual Private Cloud (VPC) segmentada para aislar los recursos públicos de los privados.​​
VPC Principal (10.0.0.0/16): Contendrá todas las subredes del proyecto.
Subred Pública (10.0.1.0/24): Conectada a un Internet Gateway (IGW). Aquí residirá la interfaz WAN del firewall perimetral.
Subred Privada de Servicios (10.0.2.0/24): Aislada de internet directamente. Aquí se alojarán los servidores de streaming y el balanceador de carga. Saldrán a internet a través de NAT.
Subred de Gestión / SOC (10.0.3.0/24): Red aislada para las herramientas de monitorización y el SIEM.
3. Desglose Técnico de los Nodos (Máquinas y Contenedores)
El proyecto consta de 5 instancias EC2 (tipo t2.micro/t3.micro basadas en Linux) y servicios desplegados mediante Docker, asumiendo roles específicos:
Nodo 1: Firewall Perimetral y Control de Acceso (Instancia EC2)
Tecnología: pfSense (Desplegado como AMI nativa o sobre FreeBSD).
Rol: Actuará como NAT Gateway para las subredes privadas e inspeccionará todo el tráfico entrante.
Portal Cautivo: Se configurará en la interfaz LAN de pfSense para simular el acceso al WiFi del estadio ("Palau_Guest_WiFi"). Interceptará el tráfico HTTP/HTTPS y obligará al usuario a aceptar los términos antes de asignar concesión DHCP o permitir el paso de paquetes hacia la subred de servicios.
Nodo 2: Balanceador de Carga / Reverse Proxy (Instancia EC2)
Tecnología: Nginx (Proxy Inverso).
Rol: Punto de entrada único para las peticiones de vídeo de los usuarios una vez han pasado el Portal Cautivo. Nginx distribuirá las peticiones HTTP (Capa 7) en formato Round-Robin o Least Connections hacia los nodos de streaming posteriores.​
Nodos 3 y 4: Clúster de Streaming HLS (2x Instancias EC2)
Tecnología: Docker Compose, ejecutando la imagen tiangolo/nginx-rtmp (Nginx compilado con el módulo RTMP).
Rol: Procesamiento de vídeo. Recibirán un flujo de vídeo estático (o simulado por OBS) por el puerto 1935 (RTMP) y lo transcodificarán sobre la marcha en fragmentos de listas de reproducción .m3u8 y segmentos .ts (HTTP Live Streaming) para ser consumidos por los clientes sin latencia.
Nodo 5: CiberSOC y Telemetría (Instancia EC2)
Contendrá el stack de seguridad y monitorización de la infraestructura, dividido en contenedores:
Wazuh Manager (SIEM): Recibirá logs centralizados. Los agentes de Wazuh instalados en pfSense, el Balanceador y los Nodos de Streaming enviarán telemetría (logs de Nginx, syslog del Portal Cautivo y del firewall).
Prometheus y Grafana: Prometheus extraerá las métricas de rendimiento (uso de CPU, peticiones concurrentes mediante nginx_stub_status) y Grafana las renderizará en un dashboard en tiempo real para el centro de control del estadio.​
Honeypot Cowrie: Desplegado en un contenedor exponiendo el puerto 2222 (mapeado como 22 para simular SSH). Registrará ataques de fuerza bruta intentando penetrar en la "red de administración del estadio".
4. Flujo de Integración y Respuesta Activa de Seguridad
El punto fuerte del proyecto es la automatización de la seguridad frente a ciberataques. Se configurará el siguiente flujo de Active Response entre Wazuh y pfSense:​
Detección: Un atacante en el anillo WiFi escanea la red interna y ataca por fuerza bruta el Honeypot Cowrie.
Recolección: El contenedor Cowrie genera un log en formato JSON con la IP origen y la contraseña intentada. El agente de Wazuh localiza este log y se lo envía al Wazuh Manager en el Nodo 5.
Correlación: Wazuh Manager procesa el JSON, detecta que la alerta supera el nivel 10 (intrusión crítica) gracias a un decodificador y regla personalizados.
Respuesta Activa: Wazuh ejecuta un script automático (Active Response) que se comunica vía API o SSH con pfSense.
Mitigación: pfSense añade la IP del atacante a una tabla del firewall (por ejemplo, wazuh-blocklist) con una regla DROP, expulsando al instante al atacante del WiFi del estadio.​
5. Pruebas de Carga y Simulación (Evaluación del Proyecto)
Para validar la arquitectura en la defensa del proyecto, se ejecutarán dos vectores simultáneos:
Carga Legítima (Estrés): Mediante Apache JMeter o K6 se inyectarán miles de peticiones HTTP recurrentes simulando a los fans consumiendo el fragmento .m3u8 de Nginx. Grafana demostrará cómo el balanceador reparte el estrés de CPU entre los nodos 3 y 4 equitativamente.
Carga Maliciosa (Ataque): Utilizando una máquina con Kali Linux, se lanzarán ataques Slowloris (DoS de capa de aplicación) y fuerza bruta contra los servicios internos para demostrar cómo Wazuh bloquea al atacante sin interrumpir el vídeo del resto de los usuarios legítimos **
