# [cite_start]Implementación de un SOC con Wazuh y Docker 

## [cite_start]1. ¿Qué es un SOC? 
[cite_start]Un **SOC (Security Operations Center)** es una unidad centralizada de la especialidad de ciberseguridad, la cual tiene la función de supervisar, detectar, analizar y responder a los incidentes sobre seguridad informática en tiempo real.

### [cite_start]¿Por qué implementar uno? 
[cite_start]En este proyecto implementaremos un SOC para tener supervisados nuestros servidores sobre ataques informáticos y analizar el posible tráfico sospechoso en la red.

---

## [cite_start]2. Instalación de Docker 

### [cite_start]Paso 1: Preparar el sistema 
[cite_start]Actualizamos las dependencias e instalamos los certificados necesarios para el funcionamiento del sistema:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
