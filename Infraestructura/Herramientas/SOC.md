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
Comandos:
sudo apt update
sudo apt install docker-ce

```
<img width="586" height="275" alt="image" src="https://github.com/user-attachments/assets/842aa716-ed07-4e03-b1d3-e0c49ddc9331" />

### 2. Añadir la llave oficial de Docker:
Lo segundo que haremos será instalar la llave oficial de Docker para que el servicio que hostearemos en los contenedores pueda funcionar correctamente.
Para ello tendremos que crear una carpeta donde alojaremos las llaves y descargarlas ahí.


```bash
Comandos utilizados:
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg


```
<img width="587" height="59" alt="image" src="https://github.com/user-attachments/assets/8b9f6c39-ad93-4059-aef1-738ae4d38d85" />

### 3. Instalación de Docker:
Proseguiremos con la instalación de Docker.
El primer comando que veremos tiene la función de decirle a nuestro ordenador desde dónde debe descargar los archivos de Docker y la verificación de estos.


```bash
Comandos utilizados:
Comandos utilizados:
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

```
<img width="589" height="56" alt="image" src="https://github.com/user-attachments/assets/b51ecf6d-7442-4fea-8a71-63e9122f9d33" />



