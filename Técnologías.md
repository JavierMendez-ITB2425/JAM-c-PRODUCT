# Tecnologías: 
En este archivo veremos diferentes tipos de herramientas que implementaremos en nuestro proyecto.

## Entornos de virtualización (Isard - AWS):
En nuestro proyecto hemos mirado diferentes tecnologías de virtualización para montar nuestros servidores; entre todas estas herramientas había 2, las cuales comparamos para seleccionarla como candidata definitiva en nuestro proyecto.
Lo primero que hicimos fue comparar ventajas y desventajas de cada una de estas 2 herramientas; por el lado de Isard, tenemos la ventaja de que podemos crear máquinas con más recursos que en AWS, pero como desventaja, publicar nuestros servicios a internet es bastante complicado y no podemos crear una red bien administrada debido a sus escasas opciones de configuración.
Por otro lado, Amazon Web Service es ampliamente configurable, pero no podemos asignar tantos recursos en las máquinas como quisiéramos.
Como resultado, elegimos AWS debido a que priorizamos la alta configuración antes que los recursos del sistema.

## Orquestación y aprovisionamiento (Terraform):
En nuestro proyecto implementaremos Terraform para tener una infraestructura de servidores con redundancia; esto debido a que, si alguna máquina por algún motivo colapsa, podremos restablecerla con esta herramienta. Además de la gran función de redundancia, podemos gestionar el estado y planificar cambios en las máquinas.
