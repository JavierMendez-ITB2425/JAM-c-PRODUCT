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
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```
<img width="589" height="56" alt="image" src="https://github.com/user-attachments/assets/b51ecf6d-7442-4fea-8a71-63e9122f9d33" />


Seguimos con la instalación oficial de Docker.

```bash
Comandos utilizados:
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```
<img width="586" height="257" alt="image" src="https://github.com/user-attachments/assets/bd5142be-4d61-4acf-afda-00b3c2fcd1e9" />

### 4. Configuración del contenedor:
En este apartado prepararemos el terreno para instalar Wazuh en Docker.
Para ello realizaremos los 2 siguientes comandos, los cuales nos sirven para permitir un alto conteo de mapas de memoria.

```bash
Comandos utilizados:
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```
<img width="583" height="77" alt="image" src="https://github.com/user-attachments/assets/7e13a476-7ccf-43b3-952d-34a3c4ea4bdb" />

### 5. Instalación de Wazuh para Docker:
Una vez tenemos todo listo, procedemos con la instalación de Wazuh en Docker.
Primero instalaremos Git debido a que no lo tenemos instalado.

```bash
Comandos utilizados:
sudo apt install git -y
```
<img width="589" height="151" alt="image" src="https://github.com/user-attachments/assets/594c796f-a5b0-4dd6-982c-ecd51d245e25" />

Una vez instalado, tendremos que clonar el repositorio oficial de Wazuh y accederemos a él.

```bash
Comandos realizados:
git clone https://github.com/wazuh/wazuh-docker.git -b v4.9.0 --depth=1
cd wazuh-docker/single-node
```
<img width="586" height="313" alt="image" src="https://github.com/user-attachments/assets/e6a3cadd-2778-496f-bb19-d0f51e0abf76" />

### 6. Generación de certificados:
Una vez tenemos instalado Wazuh en Docker, procederemos con la generación de los certificados.

```bash
Comando realizado:
docker compose -f generate-indexer-certs.yml run --rm generator
```
<img width="590" height="146" alt="image" src="https://github.com/user-attachments/assets/1f459b3a-4b7c-481c-801d-7285e5861acf" />

### 7. Despliegue de contenedores:
Una vez tenemos todo listo, procederemos con el lanzamiento de contenedores y la verificación de estos.

```bash
Comandos utilizados:
docker compose up -d
docker compose logs -f
```
<img width="590" height="293" alt="image" src="https://github.com/user-attachments/assets/5d37f465-e98e-41de-be43-a0f4de98d394" />

---

<img width="587" height="293" alt="image" src="https://github.com/user-attachments/assets/c188a6bc-5ce9-46a8-aecc-956a37a729b5" />

### 8. Por último, verificaremos que todo funcione correctamente. 
Ahora nos quedará verificar que el funcionamiento sea correcto del servicio.

<img width="595" height="198" alt="image" src="https://github.com/user-attachments/assets/5e5fea0f-df5a-48f1-a4f9-48fafdc59cbf" />

Como se puede ver podemos entrar lo que significa que funciona correctamente.

### 9. Configuración para que analice nuestras máquinas. 
Una vez sabemos que el servicio funciona correctamente, procederemos con la configuración para que analice todas nuestras máquinas.

<img width="592" height="28" alt="image" src="https://github.com/user-attachments/assets/6188595d-0d76-4efd-800a-2774c98f3ab5" />

---

<img width="586" height="151" alt="image" src="https://github.com/user-attachments/assets/9cf07780-987b-4ef1-ab06-1ec482cdd14b" />


Lo que hemos realizado en estas 2 capturas adjuntadas es entrar dentro del contenedor, instalar nano para posteriormente editar el archivo (/var/ossec/etc/ossec.conf).

## 9.1 El archivo (/var/ossec/etc/ossec.conf):
En este archivo modificaremos un apartado para permitir el acceso de Wazuh a las subredes donde se encuentran nuestras máquinas; esto nos servirá para que Wazuh pueda analizarlas y realizar su trabajo.

<img width="381" height="133" alt="image" src="https://github.com/user-attachments/assets/4ac9ae11-6a9c-40a2-8e46-991f2ad450af" />

---

<img width="587" height="278" alt="image" src="https://github.com/user-attachments/assets/7898b345-dad0-41e4-b6c2-c147db3e9d60" />

### 10. Instalación de Wazuh en todas las máquinas:
De las últimas acciones que realizaremos para que Wazuh pueda funcionar correctamente será instalar el agente de Wazuh en todas las máquinas que queremos monitorizar.

<img width="590" height="225" alt="image" src="https://github.com/user-attachments/assets/4bd87eb2-dcc7-414c-90d3-f046c9036b4c" />

### 11. Recolección de logs por grupo:
Por último, agruparemos las máquinas por grupos; en un lado tenemos el grupo de “Visitantes”, donde se encontrarán las máquinas de Nginx, web e iperf4, y en el otro lado el grupo “Gestión”, donde encontramos las máquinas icecast y el balanceador de carga.

Una vez agrupadas las máquinas, modificaremos el código en cada grupo para que recolecte la información que queremos.
<img width="589" height="166" alt="image" src="https://github.com/user-attachments/assets/f05741d2-2204-489b-b37f-7a1665a2ce2f" />

#### Visitantes:
<img width="592" height="391" alt="image" src="https://github.com/user-attachments/assets/ee6afb68-1d73-4880-a5fd-2543f8a3d521" />

#### Gestión:
<img width="590" height="399" alt="image" src="https://github.com/user-attachments/assets/d3a8521c-d3a1-4bf4-9342-d76adc3eeb2c" />





