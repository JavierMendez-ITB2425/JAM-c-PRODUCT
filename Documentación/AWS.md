# Infraestructura de Red AWS 
 
## Índice
 
1. [La VPC — El Contenedor de Todo](#1-la-vpc--el-contenedor-de-todo)
2. [El Internet Gateway](#2-el-internet-gateway)
3. [Las Subredes](#3-las-subredes)
4. [Las Route Tables — Cómo Viajan los Paquetes](#4-las-route-tables--cómo-viajan-los-paquetes)
5. [Los Security Groups — El Firewall de AWS](#5-los-security-groups--el-firewall-de-aws)
6. [La ENI y el Source/Destination Check](#6-la-eni-y-el-sourcedestination-check)
7. [Las IPs Elásticas](#7-las-ips-elásticas)
8. [Las Instancias EC2 y su Posición en la Red](#8-las-instancias-ec2-y-su-posición-en-la-red)
9. [Flujos de Tráfico Completos](#9-flujos-de-tráfico-completos)
10. [Resumen Visual de la Arquitectura](#10-resumen-visual-de-la-arquitectura)
---
 
## 1. La VPC — El Contenedor de Todo
 
```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}
```
 
La VPC (Virtual Private Cloud) es la red privada virtual que AWS
crea de forma aislada para el proyecto. Todo lo que se despliega
en este proyecto vive dentro de esta VPC y nada externo puede
acceder a ella salvo por los puntos de entrada que se definan
explícitamente.
 
El bloque CIDR `10.0.0.0/16` define el espacio de direcciones IP
disponible. La notación /16 significa que los dos primeros octetos
(10.0) son fijos y los dos últimos son variables, dando un total
de 65.536 direcciones IP posibles (de 10.0.0.0 a 10.0.255.255).
De ese espacio total se han asignado cinco subredes, cada una con
un /24 (256 direcciones por subred).
 
`enable_dns_hostnames = true` permite que las instancias dentro
de la VPC tengan nombres DNS internos además de IPs. Esto
facilita la comunicación entre servicios por nombre en lugar
de por IP.
 
---
 
## 2. El Internet Gateway
 
```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}
```
 
El Internet Gateway (IGW) es el componente que conecta la VPC
con internet. Sin él, ningún tráfico puede entrar ni salir de
la red hacia el exterior, independientemente de cualquier otra
configuración.
 
El IGW es un componente gestionado por AWS — no es una máquina
virtual ni consume recursos de cómputo propios. Tiene capacidad
ilimitada y alta disponibilidad garantizada por AWS.
 
Sin embargo, el IGW por sí solo no hace nada. Para que una subred
tenga acceso a internet, su Route Table debe tener una ruta que
apunte al IGW. Solo las subredes con esa ruta pueden comunicarse
con el exterior.
 
En este proyecto, dos subredes tienen ruta directa al IGW:
la subnet del Firewall WAN y la subnet DMZ. El resto de subredes
privadas no apuntan al IGW — su tráfico externo pasa por
el firewall EC2.
 
---
 
## 3. Las Subredes
 
Una subred es una división del espacio de direcciones de la VPC.
Cada instancia EC2 vive en exactamente una subred y recibe una
IP dentro del rango de esa subred. Las subredes son la base
de la segmentación de red del proyecto.
 
### Subnet Firewall WAN — 10.0.0.0/24
 
```hcl
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "us-east-1a"
}
```
 
Es la única subred verdaderamente pública del proyecto además
de la DMZ. Aquí vive la única interfaz del firewall EC2. Al tener
una ruta directa al IGW y una IP elástica asignada, esta subred
es el único punto de entrada SSH al proyecto entero.
 
Las instancias en esta subred pueden recibir tráfico desde
internet directamente, sin intermediarios.
 
### Subnet Visitantes — 10.0.3.0/24
 
```hcl
resource "aws_subnet" "visitantes" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}
```
 
Subred privada que simula la red WiFi pública del recinto.
No tiene ruta directa al IGW — todo su tráfico externo pasa
por el firewall. Las instancias aquí no son accesibles desde
internet directamente.
 
Aloja el portal cautivo Nginx y la máquina iPerf3.
 
### Subnet Gestión — 10.0.4.0/24
 
```hcl
resource "aws_subnet" "gestion" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1a"
}
```
 
Subred privada que aloja toda la infraestructura de streaming
y la base de datos. Es la subred con más tráfico interno del
proyecto — los nodos HLS generan y sirven fragmentos de vídeo
continuamente.
 
Al igual que Visitantes, no tiene acceso directo a internet.
Sale al exterior a través del firewall.
 
Aloja el balanceador (10.0.4.242), HLS1 (10.0.4.195),
HLS2 (10.0.4.166) y la base de datos MySQL (10.0.4.10).
Las IPs fijas se declaran en Terraform con `private_ip` para
que sean siempre predecibles independientemente de cuántas
veces se recree la instancia.
 
### Subnet DMZ — 10.0.5.0/24
 
```hcl
resource "aws_subnet" "dmz" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"
}
```
 
Subred semipública. Tiene su propia ruta directa al IGW,
lo que la diferencia de las subredes privadas. El web server
de la DMZ (10.0.5.50) es accesible desde internet directamente
a través de su IP elástica, sin pasar por el firewall.
 
Sin embargo, el tráfico entre la DMZ y las subredes internas
sí pasa por el firewall, que aplica las reglas iptables
correspondientes.
 
### Subnet SOC — 10.0.6.0/24
 
```hcl
resource "aws_subnet" "soc" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1a"
}
```
 
Subred privada completamente aislada de Visitantes por iptables.
Aloja el nodo SOC Core con Wazuh, Grafana y Prometheus.
 
Aunque el tráfico externo pasa por el firewall como el resto
de subredes privadas, iptables bloquea específicamente cualquier
intento de comunicación desde Visitantes hacia esta subred.
Gestión y SOC sí pueden comunicarse entre sí para el envío
de logs de los agentes Wazuh.
 
---
 
## 4. Las Route Tables — Cómo Viajan los Paquetes
 
Las Route Tables son las tablas de enrutamiento que determinan
hacia dónde se envía cada paquete que sale de una subred. Cada
subred tiene exactamente una Route Table asociada.
 
### Route Table del Firewall WAN
 
```hcl
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
 
resource "aws_route_table_association" "assoc_public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt_public.id
}
```
 
La ruta `0.0.0.0/0` significa "cualquier destino no conocido
de otra forma". Al apuntar al IGW, cualquier paquete que salga
de la subnet del Firewall WAN con destino a una IP externa
se envía al Internet Gateway y de ahí a internet.
 
Esta es la única ruta definida porque AWS añade automáticamente
una ruta `10.0.0.0/16 → local` en todas las Route Tables, que
permite la comunicación entre todas las subredes de la VPC
sin configuración adicional.
 
### Route Tables de las Subredes Privadas
 
```hcl
resource "aws_route_table" "rt_visitantes" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.fw_wan.id
  }
}
```
 
El mismo patrón se repite para Visitantes, Gestión y SOC.
La diferencia crítica respecto a la Route Table del Firewall
WAN es el destino: en lugar de apuntar al IGW, apuntan a la
ENI (interfaz de red) del firewall EC2.
 
Esto significa que cualquier paquete que salga de estas subredes
con destino externo llega primero al firewall. El firewall
decide si lo deja pasar (aplicando NAT para que salga con
su IP pública) o lo bloquea.
 
La implicación importante es que el firewall ve absolutamente
todo el tráfico que entra y sale de las subredes privadas,
lo que lo convierte en el punto central de control y
monitorización de la red.
 
### Route Table de la DMZ
 
```hcl
resource "aws_route_table" "rt_dmz" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
```
 
La DMZ tiene su propia Route Table idéntica a la del Firewall
WAN — apunta directamente al IGW. Esto es lo que la convierte
técnicamente en una DMZ: tiene salida directa a internet sin
pasar por el firewall EC2.
 
El control de qué tráfico puede entrar en la DMZ desde internet
lo ejerce el Security Group sg_dmz, no las Route Tables.
 
---
 
## 5. Los Security Groups — El Firewall de AWS
 
Los Security Groups son el primer nivel de seguridad perimetral
que aplica AWS antes de que cualquier paquete llegue a una
instancia EC2. Funcionan como un firewall con estado (stateful)
a nivel de instancia.
 
Al ser stateful, si se permite el tráfico de entrada en
un puerto, las respuestas a ese tráfico se permiten
automáticamente sin necesidad de una regla de salida explícita.
 
### sg_firewall — Security Group del Firewall EC2
 
```hcl
resource "aws_security_group" "sg_firewall" {
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```
 
Este SG define qué tráfico puede llegar al firewall EC2 desde
el exterior.
 
Los puertos 22, 80 y 443 están abiertos desde `0.0.0.0/0`
(cualquier IP de internet). El 22 permite el acceso SSH para
administración. El 80 y 443 son necesarios para el DNAT —
cuando alguien desde internet accede a la IP pública del
firewall en estos puertos, las reglas iptables redirigen
ese tráfico hacia los servicios internos (Wazuh en SOC).
 
La regla `protocol = "-1"` con origen `10.0.0.0/16` permite
todo el tráfico que venga de dentro de la VPC. Esto es esencial
porque el firewall necesita recibir los paquetes de todas las
subredes privadas para poder enrutarlos y aplicar NAT.
 
La regla de egress permite todo el tráfico saliente sin
restricciones, ya que el firewall necesita reenviar paquetes
hacia cualquier destino.
 
### sg_servicios — Security Group de las Subredes Internas
 
```hcl
resource "aws_security_group" "sg_servicios" {
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```
 
Este SG se aplica a todas las instancias de subredes privadas:
Visitantes, Gestión y SOC. La regla de ingress permite todo
el tráfico que venga de dentro de la VPC (10.0.0.0/16)
y bloquea implícitamente cualquier tráfico directo desde
internet.
 
El bloqueo de tráfico externo directo es automático — si no
hay una regla que lo permita, AWS lo descarta. Una instancia
con este SG solo puede recibir conexiones desde otras máquinas
de la misma VPC.
 
La granularidad de qué subred puede hablar con qué otra la
gestiona iptables en el firewall, no este SG. El SG es la
barrera exterior; iptables es la barrera interior.
 
### sg_dmz — Security Group Exclusivo de la DMZ
 
```hcl
resource "aws_security_group" "sg_dmz" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```
 
Este SG es lo que técnicamente distingue a la DMZ del resto
de subredes a nivel de AWS. A diferencia de sg_servicios,
permite tráfico HTTP y HTTPS desde `0.0.0.0/0` — es decir,
desde cualquier IP de internet.
 
El puerto 22 solo está permitido desde dentro de la VPC
(10.0.0.0/16), lo que significa que la administración SSH
del web server solo es posible mediante ProxyJump a través
del firewall, nunca directamente desde internet.
 
---
 
## 6. La ENI y el Source/Destination Check
 
```hcl
resource "aws_network_interface" "fw_wan" {
  subnet_id         = aws_subnet.public.id
  security_groups   = [aws_security_group.sg_firewall.id]
  source_dest_check = false
}
```
 
La ENI (Elastic Network Interface) es la interfaz de red virtual
que se asocia al firewall EC2. Se crea como recurso independiente
para poder asignarle la IP elástica y referenciarla desde
las Route Tables de las subredes privadas.
 
El parámetro `source_dest_check = false` es el más importante
de toda la configuración de red. Por defecto, AWS verifica
que el origen y destino de cada paquete que pasa por una
instancia coincidan con la IP de esa instancia. Si no coinciden,
AWS descarta el paquete.
 
Este comportamiento por defecto tiene sentido para instancias
normales — una EC2 solo debería enviar y recibir su propio
tráfico. Pero el firewall necesita reenviar paquetes de otras
instancias: recibe un paquete de 10.0.3.5 (Visitantes) con
destino 8.8.8.8 (internet) y lo reenvía. La IP origen
(10.0.3.5) no coincide con la IP del firewall, por lo que
AWS lo descartaría.
 
Al desactivar este check, el firewall puede actuar como
router y NAT, que es exactamente su función en la arquitectura.
 
Sin `source_dest_check = false`, las subredes privadas
no tendrían internet y no podrían comunicarse entre sí
a través del firewall.
 
---
 
## 7. Las IPs Elásticas
 
Una IP elástica es una dirección IP pública fija asignada a
la cuenta de AWS. A diferencia de las IPs públicas normales,
que cambian cada vez que una instancia se reinicia, una IP
elástica permanece constante independientemente del ciclo
de vida de la instancia.
 
### IP Elástica del Firewall
 
```hcl
resource "aws_eip" "fw_eip" {
  instance   = aws_instance.firewall.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}
```
 
Es la IP pública fija del firewall. Al ser el único punto
de entrada SSH al proyecto, necesita una IP estable para
poder conectarse siempre con el mismo comando. También
es la IP que aparece como origen de todo el tráfico que
sale de las subredes privadas hacia internet, ya que el
firewall aplica NAT masquerade.
 
El atributo `depends_on` garantiza que Terraform no intente
asignar la IP elástica antes de que el Internet Gateway exista.
Sin él, la asociación fallaría porque AWS requiere un IGW
activo para poder asignar IPs elásticas en una VPC.
 
### IP Elástica de la DMZ
 
```hcl
resource "aws_eip" "dmz_eip" {
  instance   = aws_instance.web_server.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}
```
 
Sin esta IP elástica, el web server de la DMZ no sería
accesible desde internet. Las instancias en subredes privadas
no reciben IP pública automáticamente en AWS a menos que
la subred tenga `map_public_ip_on_launch = true` o se asigne
explícitamente una IP elástica.
 
Al tener la DMZ su propia Route Table apuntando al IGW
y esta IP elástica asignada al web server, los usuarios
de internet pueden acceder directamente a la web del Palau
sin pasar por ningún intermediario.
 
---
 
## 8. Las Instancias EC2 y su Posición en la Red
 
Cada instancia EC2 se sitúa en una subred concreta mediante
el atributo `subnet_id` y recibe los permisos de red del
Security Group asignado. Algunas instancias tienen además
IPs privadas fijas declaradas explícitamente.
 
### IPs Privadas Fijas
 
```hcl
resource "aws_instance" "balanceador_gestion" {
  private_ip = "10.0.4.242"
}
 
resource "aws_instance" "icecast" {
  private_ip = "10.0.4.195"
}
 
resource "aws_instance" "ftp" {
  private_ip = "10.0.4.166"
}
 
resource "aws_instance" "database" {
  private_ip = "10.0.4.10"
}
 
resource "aws_instance" "web_server" {
  private_ip = "10.0.5.50"
}
```
 
Las IPs fijas son necesarias cuando otros servicios necesitan
referenciar una máquina por IP de forma constante. En este
proyecto hay tres casos de uso:
 
El balanceador tiene IP fija porque la configuración de HAProxy
en los nodos HLS y la configuración del proxy en Visitantes
apuntan a `10.0.4.242`. Si la IP cambiara al recrear la
instancia, todas esas configuraciones dejarían de funcionar.
 
Los nodos HLS1 y HLS2 tienen IP fija porque HAProxy los
referencia directamente en `haproxy.cfg` y el comando FFmpeg
también apunta a ellos por IP.
 
La base de datos tiene IP fija porque el web server de la DMZ
y las reglas iptables del firewall la referencian directamente.
 
El web server de la DMZ tiene IP fija porque la regla iptables
que permite el acceso de la DMZ a la base de datos está
escrita con esa IP concreta como origen.
 
### Instancias sin IP Fija
 
```hcl
resource "aws_instance" "portal_cautivo" {
  subnet_id = aws_subnet.visitantes.id
}
 
resource "aws_instance" "soc_core" {
  subnet_id = aws_subnet.soc.id
}
```
 
Las instancias que no tienen `private_ip` declarada reciben
una IP dinámica dentro del rango de su subred en cada
despliegue. Esto es aceptable cuando ninguna otra máquina
las referencia directamente por IP en sus configuraciones.
 
---

## 9. Resumen Visual de la Arquitectura
 
```
                        INTERNET
                           |
                    [Internet Gateway]
                    (recurso de AWS)
                           |
              ┌────────────┴────────────┐
              |                         |
    [IP Elástica Firewall]    [IP Elástica DMZ]
    (acceso SSH + DNAT)       (web pública)
              |                         |
    ┌─────────┴─────────┐    ┌──────────┴──────────┐
    | SUBNET FIREWALL   |    | SUBNET DMZ          |
    | 10.0.0.0/24       |    | 10.0.5.0/24         |
    | sg_firewall       |    | sg_dmz              |
    | EC2 Firewall      |    | EC2 Web Server      |
    | ENI source_dest   |    | IP fija 10.0.5.50   |
    |   _check=false    |    | RT → IGW directo    |
    └─────────┬─────────┘    └─────────────────────┘
              |
    (todas las RT privadas apuntan a esta ENI)
              |
    ┌─────────┼─────────────────────┐
    |         |                     |
┌───┴────┐ ┌──┴──────┐        ┌────┴───┐
|SUBNET  | |SUBNET   |        |SUBNET  |
|VISIT.  | |GESTIÓN  |        |SOC     |
|10.0.3  | |10.0.4   |        |10.0.6  |
|sg_serv | |sg_serv  |        |sg_serv |
|        | |         |        |        |
|Portal  | |Balancead| ←RTMP→ |SOC Core|
|web     | |HLS1     |        |Wazuh   |
|        | |HLS2     |        |        |
|        | |MySQL    |        |Cowrie  |
└────────┘ └─────────┘        └────────┘
 
