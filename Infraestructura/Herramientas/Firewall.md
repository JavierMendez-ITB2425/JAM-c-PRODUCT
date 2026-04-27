**Configuración Firewall**

Para el despliegue del perímetro de seguridad y la gestión de acceso del recinto, se ha seleccionado **pfSense** como la pieza central de la infraestructura. pfSense es una solución de firewall y enrutamiento de código abierto basada en **FreeBSD**, reconocida por su estabilidad y potencia en entornos de producción real.

La elección de pfSense no es arbitraria; responde a la necesidad de integrar múltiples servicios críticos en un solo punto de gestión:

* **Robustez como Firewall Perimetral:** Permite una inspección profunda de paquetes (DPI) y un control estricto del tráfico entrante y saliente, actuando como la primera línea de defensa del recinto.  
* **Capacidad de Enrutamiento y NAT:** Actuará como el **NAT Gateway** para las subredes privadas (Servicios y SOC), permitiendo que los servidores internos tengan salida a internet de forma segura sin exponer sus IPs privadas directamente.  
* **Gestión de Acceso Masivo (Captive Portal):** Es la herramienta ideal para simular el WiFi del estadio/local/establecimiento. El portal cautivo permite interceptar el tráfico y obligar a una validación previa antes de permitir la navegación.  
* **Extensibilidad para Ciberseguridad (Blue Team):** A diferencia de otros firewalls cerrados, pfSense facilita la integración con sistemas externos. Esto es vital para ejecutar la **Respuesta Activa** desde el Nodo 5 (Wazuh), permitiendo el bloqueo dinámico de atacantes mediante scripts o API


Dentro de nuestro diseño en AWS, el Nodo 1 no es solo un servidor más; es el **nexo de unión** entre la capa pública y la privada. Su función principal es garantizar que el flujo de vídeo y los servicios de monitorización permanezcan operativos incluso bajo intentos de intrusión, separando el tráfico de los fans del tráfico de administración.

**Infraestructura AWS**  
**Configuración Security Group:**

- **SG-Firewall:**  
  - Inbound: SHH (22) desde “My IP”.  
  - Outbound: Todo a todo (0.0.0.0/0).

- **SG-Nodos-Privados:**  
  - Inbound: SSH (22) solo desde el ID del SG-Firewall.  
  - Inbound: ICMP (Ping) desde el rango de red de la VPC (ej: 10.0.0.0/16).  
  - Outbound: Todo (o restringido a tu gusto).

![image1](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/1.png)

**Source/Destination Check:** Una vez lanzada la instancia Firewall, ve a la consola, *Acciones \> Redes \> Cambiar comprobación de origen/destino* y **Detenerla**. Esto es innegociable.  
![image2](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/2.png) 

**Route Tables:** En la Route Table de la subred privada, crea la ruta: *0.0.0.0/0* apuntando al **Network Interface ID** de tu Firewall.  
![image3](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/3.png)

**Modificación del archivo netplan:**  
Modificaremos este archivo para darle la IP x.x.x.1 a nuestro firewall.  
**Comando:**  
**sudo nano /etc/netplan/50-cloud-init.yaml**  
![image4](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/4.png)

**Configuración iptables**  
**Habilitamos NAT (Enmascaramiento)**  
Esto va a permitir que los nodos (que no tienen IP pública) puedan salir a internet a través de la interfaz pública.  
**Comando:**  
**sudo iptables \-t nat \-A POSTROUTING \-o eth0 \-j MASQUERADE && sudo iptables \-A FORWARD \-j ACCEPT**  
![image5](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/5.png)  
**Permitir el tráfico ya establecido:**  
Este es el comando más importante. Le dice al firewall: "Si yo inicié una conexión, deja que los paquetes de respuesta vuelvan". Sin esto, aunque permitas la entrada, las respuestas a tus peticiones serían bloqueadas y nada funciona.  
**Comandos:**  
**sudo iptables \-A INPUT \-m conntrack \--ctstate ESTABLISHED,RELATED \-j ACCEPT**  
**sudo iptables \-A FORWARD \-m conntrack \--ctstate ESTABLISHED,RELATED \-j ACCEPT**  
![image6](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/6.png)  
“Conntrack” rastrea las conexiones. Si la conexión ya es conocida (ya pasó por el firewall antes), se acepta automáticamente.

**Permitimos el tráfico local (Loopback)**  
Tu propia máquina (el firewall) necesita hablar consigo misma. Muchos servicios internos fallarán si bloqueas el tráfico "interno".  
**Comando:**  
**sudo iptables \-A INPUT \-i lo \-j ACCEPT**  
![image7](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/7.png)  
“lo” es la interfaz de loopback (localhost). Es vital para que los procesos internos del sistema operativo se comuniquen entre sí.

**Aseguramos el acceso SSH**  
Este comando permite explícitamente el tráfico SSH (puerto 22).

**Nota:** debemos asegurarnos de que tenemos la llave antes de cerrar cualquier puerta:  
![image8](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/8.png)

**Comando:**  
**sudo iptables \-A INPUT \-p tcp \--dport 22 \-j ACCEPT**  
![image9](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/9.png)  
“dport 22” es el puerto estándar de SSH. Esto garantiza que tu conexión actual no se corte cuando pongamos la política restrictiva al final.

**Permitimos el tráfico de las subredes** **(Gestión, Visitantes, SOC)**  
Ahora permitimos que tus subredes internas (10.0.6.0/24, 10.0.3.0/24, 10.0.4.0/24) puedan atravesar el firewall.  
**Comandos:**  
**sudo iptables \-A FORWARD \-s 10.0.6.0/24 \-j ACCEPT**  
**sudo iptables \-A FORWARD \-s 10.0.3.0/24 \-j ACCEPT**  
**sudo iptables \-A FORWARD \-s 10.0.4.0/24 \-j ACCEPT**  
![image10](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/10.png)  
Con esto, los paquetes que vienen de esas subredes tienen permiso para ser reenviados (**FORWARD**) a través del firewall (hacia internet o hacia otras subredes).

**El "Cierre de Seguridad" (Política por defecto)**  
Ahora que hemos permitido todo lo necesario, vamos a configurar el firewall para que **bloquee todo lo que no esté en la lista**. Esto es lo que hace que tu red sea segura.  
**Comandos:**  
**sudo iptables \-P INPUT DROP**  
**sudo iptables \-P FORWARD DROP**  
![image11](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/11.png)  
**\-P** cambia la política por defecto. Ahora, si alguien intenta conectarse a un puerto que no hemos abierto explícitamente, el firewall lo descartará (**DROP**) inmediatamente.

**Persistencia de las reglas**  
Para que las reglas estén aplicadas hasta después del reinicio instalaremos **iptables-persistent (sudo apt update && sudo apt install \-y iptables-persistent)** y ejecutaremos el siguiente comando.  
**Comando:**  
**sudo netfilter-persistent save**  
![image12](https://github.com/JavierMendez-ITB2425/JAM-c-PRODUCT/blob/main/Infraestructura/Herramientas/src%20firewall/12.png)  


