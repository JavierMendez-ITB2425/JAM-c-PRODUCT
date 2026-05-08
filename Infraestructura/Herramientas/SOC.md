# Implementación de un SOC con Wazuh y Docker 

## 1. ¿Qué es un SOC? 
Un **SOC (Security Operations Center)** es una unidad centralizada de la especialidad de ciberseguridad, la cual tiene la función de supervisar, detectar, analizar y responder a los incidentes sobre seguridad informática en tiempo real.

### ¿Por qué vamos a implementar uno en nuestro proyecto? 
En nuestro proyecto implementaremos un SOC debido a que nos servirá para tener supervisados nuestros servidores sobre ataques informáticos; aparte de esto, nos servirá para analizar el posible tráfico sospechoso en nuestros servidores.

---

# Docker:

## Pasos para la instalación:  

### 1. Preparar el terreno (instalar Docker)
Lo primero que haremos será actualizar dependencias e instalar los certificados necesarios para que todo funcione correctamente.

```bash
# Aquí van tus comandos
sudo apt update
sudo apt install docker-ce

```

<img width="1722" height="790" alt="image" src="https://github.com/user-attachments/assets/c30e141f-9d30-46dc-993b-898092f3e00a" />


