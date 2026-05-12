# Tecnologías: 
En este archivo veremos diferentes tipos de herramientas que implementaremos en nuestro proyecto.

## Entornos de virtualización (Isard - AWS):
En nuestro proyecto hemos mirado diferentes tecnologías de virtualización para montar nuestros servidores; entre todas estas herramientas había 2, las cuales comparamos para seleccionarla como candidata definitiva en nuestro proyecto.
Lo primero que hicimos fue comparar ventajas y desventajas de cada una de estas 2 herramientas; por el lado de Isard, tenemos la ventaja de que podemos crear máquinas con más recursos que en AWS, pero como desventaja, publicar nuestros servicios a internet es bastante complicado y no podemos crear una red bien administrada debido a sus escasas opciones de configuración.
Por otro lado, Amazon Web Service es ampliamente configurable, pero no podemos asignar tantos recursos en las máquinas como quisiéramos.
Como resultado, elegimos AWS debido a que priorizamos la alta configuración antes que los recursos del sistema.

## Orquestación y aprovisionamiento (Terraform):
En nuestro proyecto implementaremos Terraform para tener una infraestructura de servidores con redundancia; esto debido a que, si alguna máquina por algún motivo colapsa, podremos restablecerla con esta herramienta. Además de la gran función de redundancia, podemos gestionar el estado y planificar cambios en las máquinas.

## Detección de amenazas y gestión de seguridad (Wazuh):
Para la monitorización y protección de nuestra infraestructura en el SCO, analizamos diferentes soluciones de gestión de eventos e información de seguridad (SIEM). Evaluamos principalmente dos alternativas: el uso de un stack ELK tradicional (Elasticsearch, Logstash y Kibana) frente a la plataforma especializada Wazuh.
Tras comparar ambas herramientas, nos decantamos por Wazuh debido a su preconfiguración de capacidades XDR y porque queríamos probar herramientas nuevas.

## Contenedores y microservicios (Docker):
En nuestro proyecto implementaremos Docker para la gestión y el despliegue de nuestras aplicaciones de forma aislada y eficiente. Elegimos esta tecnología porque nos permite empaquetar cada servicio con sus dependencias necesarias, garantizando que funcionen correctamente en cualquier entorno, sin importar la configuración del sistema operativo base. Además, Docker nos ofrece una gran ligereza en comparación con las máquinas virtuales tradicionales, lo que optimiza el uso de los recursos en nuestras instancias de AWS y facilita enormemente la escalabilidad de la infraestructura. Como resultado, decidimos integrar Docker para asegurar una portabilidad total de los servicios y una administración más ágil de cada componente del proyecto.

## Servidor Web y Proxy Inverso (Nginx):
Para la gestión del tráfico de red y la exposición de nuestros servicios, hemos implementado Nginx. Esta herramienta actúa como un proxy inverso, permitiéndonos centralizar las peticiones externas y redirigirlas de forma eficiente a los diferentes contenedores de Docker. Lo elegimos por su alto rendimiento, su capacidad para gestionar certificados SSL de forma centralizada y por la facilidad que ofrece al realizar balanceo de carga, asegurando que nuestras aplicaciones sean accesibles de manera segura y organizada.

## Seguridad de Red y Filtrado de Paquetes (Iptables):
Como capa de seguridad adicional a nivel de kernel, utilizaremos iptables para gestionar el flujo de tráfico de red en nuestras instancias. Mientras que AWS proporciona Security Groups, iptables nos permite un control mucho más granular dentro del propio sistema operativo, permitiéndonos definir reglas estrictas sobre qué puertos y direcciones IP pueden comunicarse con nuestros servicios. Es una pieza clave para mitigar ataques de red y establecer políticas de comunicación seguras entre el host y los contenedores.

Desarrollo Frontend (HTML5, CSS3 y JavaScript):
Para la interfaz de usuario de nuestro proyecto, utilizaremos el estándar de la web: HTML, CSS y JavaScript.

* HTML5 nos permite estructurar el contenido de la web de forma semántica.

* CSS3 se encarga del diseño visual y la adaptabilidad (Responsive Design) para que la plataforma sea accesible desde cualquier dispositivo.

* JavaScript aporta la lógica en el lado del cliente, permitiendo crear una experiencia dinámica e interactiva.
La combinación de estas tecnologías nos asegura una total compatibilidad con los navegadores modernos y una gran flexibilidad para escalar el frontend según las necesidades del proyecto.

Gestión de Base de Datos Relacional (MariaDB):
Como sistema de gestión de bases de datos (RDBMS), hemos seleccionado MariaDB. Decidimos implementar esta tecnología por ser una de las bases de datos de código abierto más robustas y populares, derivada de MySQL pero con mejoras en rendimiento y seguridad. En nuestro entorno de Docker, MariaDB nos permite gestionar la persistencia de los datos de manera eficiente, integrándose perfectamente con el resto de servicios y asegurando la integridad de la información de nuestro proyecto mediante un motor de almacenamiento rápido y confiable.
