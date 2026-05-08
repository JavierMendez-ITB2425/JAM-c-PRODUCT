**¿Qué es un SOC?** Un SOC (Security Operations Center) es una unidad centralizada de la especialidad de ciberseguridad, la cual tiene la función de supervisar, detectar, analizar y responder a los incidentes sobre seguridad informática en tiempo real.

**¿Por qué vamos a implementar uno en nuestro proyecto?**

En nuestro proyecto implementaremos un SOC debido a que nos servirá para tener supervisados nuestros servidores sobre ataques informáticos; aparte de esto, nos servirá para analizar el posible tráfico sospechoso en nuestros servidores.

**Docker:**\


**Pasos para la instalación:**

**1. Preparar el terreno (instalar Docker)**

Lo primero que haremos será actualizar dependencias e instalar los certificados necesarios para que todo funcione correctamente.

|<p>**Comandos utilizados:**<br>sudo apt update</p><p>sudo apt install -y ca-certificates curl gnupg lsb-release</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.001.png)</p>|
| :- |

**2. Añadir la llave oficial de Docker:**

Lo segundo que haremos será instalar la llave oficial de Docker para que el servicio que hostearemos en los contenedores pueda funcionar correctamente.

Para ello tendremos que crear una carpeta donde alojaremos las llaves y descargarlas ahí.

|<p>**Comandos utilizados:**</p><p>sudo mkdir -p /etc/apt/keyrings</p><p>curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.002.png)</p>|
| :- |

**3. Instalación de Docker:**

Proseguiremos con la instalación de Docker.

El primer comando que veremos tiene la función de decirle a nuestro ordenador desde dónde debe descargar los archivos de Docker y la verificación de estos.

|<p>**Comandos utilizados:**</p><p>echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb\_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.003.png)</p>|
| :- |

Seguimos con la instalación oficial de Docker.

|<p>**Comandos utilizados:**</p><p>sudo apt update</p><p>sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.004.png)</p>|
| :- |

**4. Configuración del contenedor:**

En este apartado prepararemos el terreno para instalar Wazuh en Docker.

Para ello realizaremos los 2 siguientes comandos, los cuales nos sirven para permitir un alto conteo de mapas de memoria.

|<p>**Comandos utilizados:**<br>sudo sysctl -w vm.max\_map\_count=262144</p><p>echo "vm.max\_map\_count=262144" | sudo tee -a /etc/sysctl.conf</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.005.png)</p>|
| :- |

**5. Instalación de Wazuh para Docker:**

Una vez tenemos todo listo, procedemos con la instalación de Wazuh en Docker.

Primero instalaremos Git debido a que no lo tenemos instalado.

|<p>**Comandos utilizados:**</p><p>sudo apt install git -y</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.006.png)</p>|
| :- |

Una vez instalado, tendremos que clonar el repositorio oficial de Wazuh y accederemos a él.

|<p>**Comandos realizados:**<br>git clone https://github.com/wazuh/wazuh-docker.git -b v4.9.0 --depth=1</p><p>cd wazuh-docker/single-node</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.007.png)</p>|
| :- |
### <a name="_nax9tyinrv0u"></a>**6. Generación de certificados:**
Una vez tenemos instalado Wazuh en Docker, procederemos con la generación de los certificados.

|<p>**Comando realizado:**<br>docker compose -f generate-indexer-certs.yml run --rm generator</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.008.png)</p>|
| :- |

**7. Despliegue de contenedores:**

Una vez tenemos todo listo, procederemos con el lanzamiento de contenedores y la verificación de estos.

|<p>**Comandos utilizados:**</p><p>docker compose up -d</p><p>docker compose logs -f</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.009.png)</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.010.png)</p>|
| :- |

**8. Por último, verificaremos que todo funcione correctamente.** 

Ahora nos quedará verificar que el funcionamiento sea correcto del servicio.

|**Funcionamiento correcto:<br>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.011.png)**|
| :- |

**9. Configuración para que analice nuestras máquinas.**

Una vez sabemos que el servicio funciona correctamente, procederemos con la configuración para que analice todas nuestras máquinas.

|<p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.012.png)</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.013.png)</p>|
| :- |

Lo que hemos realizado en estas 2 capturas adjuntadas es entrar dentro del contenedor, instalar nano para posteriormente editar el archivo (/var/ossec/etc/ossec.conf).

**9.1 El archivo (/var/ossec/etc/ossec.conf):**\
En este archivo modificaremos un apartado para permitir el acceso de Wazuh a las subredes donde se encuentran nuestras máquinas; esto nos servirá para que Wazuh pueda analizarlas y realizar su trabajo.

|<p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.014.png)</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.015.png)</p>|
| :- |

**10. Instalación de Wazuh en todas las máquinas:**

De las últimas acciones que realizaremos para que Wazuh pueda funcionar correctamente será instalar el agente de Wazuh en todas las máquinas que queremos monitorizar.

|![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.016.png)|
| :- |

\
**11. Recolección de logs por grupo**

Por último, agruparemos las máquinas por grupos; en un lado tenemos el grupo de “Visitantes”, donde se encontrarán las máquinas de Nginx, web e iperf4, y en el otro lado el grupo “Gestión”, donde encontramos las máquinas icecast y el balanceador de carga.

Una vez agrupadas las máquinas, modificaremos el código en cada grupo para que recolecte la información que queremos.

|<p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.017.png)</p><p></p><p>**Visitantes:**</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.018.png)</p><p>**Gestión:**</p><p>![](Aspose.Words.e08e3585-1186-4ac0-984d-fcf1d0ed90db.019.png)</p>|
| :- |

