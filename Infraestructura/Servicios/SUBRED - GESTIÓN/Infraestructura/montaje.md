# Instalación del Sistema de Streaming 
 
## Índice
 
1. [Requisitos Previos](#1-requisitos-previos)
2. [Acceso a las Máquinas](#2-acceso-a-las-máquinas)
3. [Fase 1 — Nodos HLS1 y HLS2](#3-fase-1--nodos-hls1-y-hls2)
4. [Fase 2 — Balanceador](#4-fase-2--balanceador)
5. [Fase 3 — Portal de Visitantes](#5-fase-3--portal-de-visitantes)
6. [Fase 4 — Arrancar el Stream](#6-fase-4--arrancar-el-stream)
7. [Correcciones Aplicadas](#7-correcciones-aplicadas)
8. [Verificación Final](#8-verificación-final)
---
 
## 1. Requisitos Previos
 
Antes de empezar la instalación deben estar operativos:
 
- Infraestructura Terraform desplegada y aplicada correctamente
- Firewall EC2 funcionando con iptables configurado
- Reglas de iptables que permiten el tráfico entre Visitantes y Gestión
  en los puertos 80, 8000 y 1935
- Vídeo pregrabado precodificado disponible para subir al balanceador
Las IPs fijas de las máquinas implicadas son:
 
| Máquina | IP | Subnet |
|---|---|---|
| Balanceador | 10.0.4.242 | Gestión |
| HLS1 | 10.0.4.195 | Gestión |
| HLS2 | 10.0.4.166 | Gestión |
| Portal Visitantes | Variable | Visitantes |
 
---
 
## 2. Acceso a las Máquinas
 
Todas las máquinas de subredes privadas son accesibles únicamente
a través del firewall como Jump Host. Antes de cualquier conexión,
añadir la clave al agente SSH local:
 
```bash
ssh-add ~/Documents/labsuser_jam.pem
```
 
Conectar a cada máquina con el siguiente patrón, sustituyendo
IP_PRIVADA por la IP correspondiente:
 
```bash
ssh -A -J ubuntu@<IP_PUBLICA_FIREWALL> ubuntu@<IP_PRIVADA>
```
 
Se recomienda abrir tres terminales simultáneas — una por cada
máquina de Gestión — para ejecutar los pasos en paralelo donde
sea posible.
 
---
 
## 3. Fase 1 — Nodos HLS1 y HLS2
 
Los dos nodos son idénticos en configuración. Ejecutar exactamente
los mismos comandos en ambos de forma simultánea.
 
### 3.1 Conectar a los nodos
 
```bash
# Terminal 1 — HLS1
ssh -A -J ubuntu@<IP_PUBLICA_FIREWALL> ubuntu@10.0.4.195
 
# Terminal 2 — HLS2
ssh -A -J ubuntu@<IP_PUBLICA_FIREWALL> ubuntu@10.0.4.166
```
 
### 3.2 Actualizar el sistema
 
```bash
sudo apt-get update && sudo apt-get upgrade -y
```
 
Este proceso puede tardar entre 2 y 5 minutos dependiendo de las
actualizaciones pendientes.
 
### 3.3 Instalar Docker
 
```bash
sudo apt-get install -y docker.io
```
 
### 3.4 Activar y arrancar Docker
 
```bash
sudo systemctl enable docker
sudo systemctl start docker
```
 
Verificar que el servicio está activo:
 
```bash
sudo systemctl status docker
```
 
La salida debe mostrar `active (running)`. Pulsar `q` para salir.
 
### 3.5 Instalar Docker Compose
 
```bash
sudo apt-get install -y docker-compose
```
 
Verificar la instalación:
 
```bash
docker-compose --version
```
 
### 3.6 Crear la estructura de carpetas
 
```bash
mkdir -p ~/streaming
```
 
### 3.7 Crear el fichero docker-compose.yml
 
**En HLS1:**
 
```bash
cat > ~/streaming/docker-compose.yml << 'EOF'
version: '3'
services:
  nginx-rtmp:
    image: tiangolo/nginx-rtmp
    container_name: nginx-origen
    ports:
      - "1935:1935"
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
    tmpfs:
      - /tmp/hls:size=300m
    restart: unless-stopped
EOF
```
 
**En HLS2:**
 
```bash
cat > ~/streaming/docker-compose.yml << 'EOF'
version: '3'
services:
  nginx-rtmp:
    image: tiangolo/nginx-rtmp
    container_name: nodo-hls
    ports:
      - "1935:1935"
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
    tmpfs:
      - /tmp/hls:size=300m
    restart: unless-stopped
EOF
```
 
La diferencia entre ambos es únicamente el `container_name`.
El parámetro `tmpfs` monta 300MB de RAM como sistema de ficheros
en `/tmp/hls`, donde nginx-rtmp escribirá los fragmentos HLS.
Al ser RAM, las operaciones de escritura son instantáneas y no
generan carga de I/O en disco.
 
### 3.8 Crear el fichero nginx.conf
 
El mismo fichero para ambos nodos:
 
```bash
cat > ~/streaming/nginx.conf << 'EOF'
worker_processes auto;
worker_rlimit_nofile 65535;
 
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}
 
rtmp {
    server {
        listen 1935;
        chunk_size 4096;
 
        application live {
            live on;
            hls on;
            hls_path /tmp/hls;
            hls_fragment 3s;
            hls_playlist_length 12s;
            hls_cleanup on;
 
            allow publish 10.0.4.242;
            deny publish all;
        }
    }
}
 
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
 
    server {
        listen 80;
 
        location / {
            add_header Cache-Control no-cache;
            add_header 'Access-Control-Allow-Origin' '*';
            alias /tmp/hls/;
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
        }
    }
}
EOF
```
 
Puntos clave de esta configuración:
 
- `hls_fragment 3s` — fragmentos de 3 segundos. Se aumentó de 2s a 3s
  para reducir el número de peticiones HTTP por visitante en un 33%.
- `hls_cleanup on` — nginx-rtmp elimina automáticamente los fragmentos
  antiguos de la RAM, evitando que se llene.
- `allow publish 10.0.4.242` — solo el balanceador puede enviar streams
  al nodo. Cualquier otro origen es rechazado.
- `use epoll` — motor de eventos de Linux más eficiente para
  manejar muchas conexiones simultáneas.
### 3.9 Levantar el contenedor
 
```bash
cd ~/streaming
sudo docker-compose up -d
```
 
La primera ejecución descarga la imagen `tiangolo/nginx-rtmp`
desde Docker Hub. Puede tardar 1-2 minutos dependiendo de la
velocidad de la conexión.
 
### 3.10 Verificar que el contenedor está corriendo
 
```bash
sudo docker ps
```
 
La salida debe mostrar el contenedor con estado `Up`:
 
```
CONTAINER ID   IMAGE                STATUS         PORTS
abc123def456   tiangolo/nginx-rtmp  Up 2 minutes   0.0.0.0:1935->1935, 0.0.0.0:80->80
```
 
### 3.11 Verificar que Nginx responde
 
```bash
curl http://localhost/
```
 
Una respuesta vacía o un código 200 confirma que el servidor HTTP
está activo y esperando peticiones.
 
---
 
## 4. Fase 2 — Balanceador
 
### 4.1 Conectar al balanceador
 
```bash
# Terminal 3
ssh -A -J ubuntu@<IP_PUBLICA_FIREWALL> ubuntu@10.0.4.242
```
 
### 4.2 Actualizar el sistema
 
```bash
sudo apt-get update && sudo apt-get upgrade -y
```
 
### 4.3 Instalar Docker, Docker Compose y FFmpeg
 
```bash
sudo apt-get install -y docker.io docker-compose ffmpeg
```
 
### 4.4 Activar Docker
 
```bash
sudo systemctl enable docker
sudo systemctl start docker
```
 
### 4.5 Verificar FFmpeg
 
```bash
ffmpeg -version
```
 
Debe devolver la versión sin errores.
 
### 4.6 Subir el vídeo pregrabado
 
El vídeo debe estar precodificado antes de este paso. Ejecutar
el siguiente comando desde el PC local, no desde la EC2:
 
```bash
scp -i labsuser_jam.pem \
    -o "ProxyJump ubuntu@<IP_PUBLICA_FIREWALL>" \
    /ruta/local/video_listo.mp4 \
    ubuntu@10.0.4.242:~/video_listo.mp4
```
 
Alternativamente, si no se dispone de vídeo propio, descargar
uno de prueba directamente en el balanceador:
 
```bash
sudo apt-get install -y wget
wget -O ~/video_listo.mp4 \
  "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"
```
 
### 4.7 Crear la estructura de carpetas
 
```bash
mkdir -p ~/balanceador
```
 
### 4.8 Crear el fichero docker-compose.yml para HAProxy
 
```bash
cat > ~/balanceador/docker-compose.yml << 'EOF'
version: '3'
services:
  haproxy:
    image: haproxy:latest
    container_name: haproxy-balanceador
    ports:
      - "80:80"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    restart: unless-stopped
EOF
```
 
### 4.9 Crear el fichero haproxy.cfg
 
```bash
cat > ~/balanceador/haproxy.cfg << 'EOF'
global
    maxconn 50000
    nbthread 2
 
defaults
    mode http
    timeout connect 3s
    timeout client  20s
    timeout server  20s
    option forwardfor
    option http-server-close
    option redispatch
 
frontend http_front
    bind *:80
    default_backend nodos_hls
 
backend nodos_hls
    balance leastconn
    option httpchk GET /stream.m3u8
    http-check expect status 200
    server hls1 10.0.4.195:80 check inter 2s fall 2 rise 1
    server hls2 10.0.4.166:80 check inter 2s fall 2 rise 1
EOF
```
 
Puntos clave de esta configuración:
 
- `balance leastconn` — dirige cada nueva petición al nodo con menos
  conexiones activas. Más eficiente que roundrobin para peticiones
  de duración variable como los fragmentos HLS.
- `option httpchk GET /stream.m3u8` — HAProxy verifica que el stream
  existe y está activo antes de mandar visitantes al nodo.
- `fall 2 rise 1` — un nodo se marca como caído tras 2 fallos
  consecutivos y se recupera con 1 respuesta exitosa.
- `nbthread 2` — usa los dos núcleos de CPU disponibles en la t3.large.
### 4.10 Levantar HAProxy
 
```bash
cd ~/balanceador
sudo docker-compose up -d
```
 
### 4.11 Verificar HAProxy
 
```bash
sudo docker ps
```
 
El contenedor `haproxy-balanceador` debe aparecer con estado `Up`.
 
---
 
## 5. Fase 3 — Portal de Visitantes
 
### 5.1 Conectar al nodo de Visitantes
 
```bash
ssh -A -J ubuntu@<IP_PUBLICA_FIREWALL> ubuntu@<IP_PORTAL_VISITANTES>
```
 
### 5.2 Instalar Nginx
 
```bash
sudo apt-get update
sudo apt-get install -y nginx
```
 
### 5.3 Configurar Nginx como proxy inverso
 
Eliminar la configuración por defecto y crear la nueva:
 
```bash
sudo rm /etc/nginx/sites-enabled/default
 
sudo cat > /etc/nginx/sites-available/portal << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
 
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    client_max_body_size 1M;
 
    location / {
        try_files $uri $uri/ =404;
    }
 
    location /hls/ {
        proxy_pass http://10.0.4.242/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
 
        proxy_buffering off;
        add_header Cache-Control no-cache;
        add_header Access-Control-Allow-Origin *;
 
        proxy_connect_timeout 3s;
        proxy_read_timeout 10s;
    }
}
EOF
 
sudo ln -s /etc/nginx/sites-available/portal /etc/nginx/sites-enabled/portal
```
 
El parámetro más importante de esta configuración es
`proxy_buffering off`. Le indica a Nginx que reenvíe los fragmentos
HLS byte a byte conforme los recibe del balanceador, sin almacenarlos
primero en memoria. Para streaming en vivo, cualquier buffer adicional
en el proxy solo añade latencia innecesaria.
 
### 5.4 Verificar la configuración
 
```bash
sudo nginx -t
```
 
Debe devolver:
```
nginx: configuration file /etc/nginx/nginx.conf test is successful
```
 
### 5.5 Reiniciar Nginx
 
```bash
sudo systemctl restart nginx
sudo systemctl enable nginx
```
 
### 5.6 Colocar la página web del portal
 
La página HTML con el reproductor HLS.js debe situarse en
`/var/www/html/index.html`. El reproductor debe apuntar a:
 
```
http://<IP_PORTAL_VISITANTES>/hls/stream.m3u8
```
 
---
 
## 6. Fase 4 — Arrancar el Stream
 
Con los nodos HLS y el balanceador listos, se arranca la emisión
desde el balanceador.
 
### 6.1 Conectar al balanceador
 
```bash
ssh -A -J ubuntu@<IP_PUBLICA_FIREWALL> ubuntu@10.0.4.242
```
 
### 6.2 Lanzar FFmpeg
 
```bash
ffmpeg \
  -re \
  -stream_loop -1 \
  -i ~/video_listo.mp4 \
  -c:v copy \
  -c:a copy \
  -bufsize 1000k \
  -max_muxing_queue_size 1024 \
  -f flv rtmp://10.0.4.195/live/stream \
  -f flv rtmp://10.0.4.166/live/stream
```
 
Parámetros clave:
 
- `-re` — emite el vídeo a velocidad real, simulando una emisión
  en directo.
- `-stream_loop -1` — repite el vídeo indefinidamente cuando
  llega al final.
- `-c:v copy` — copia el vídeo sin recodificar. Este parámetro
  es el más importante: elimina la transcodificación en tiempo real
  y reduce el consumo de CPU del 100% al 15-20%.
- `-c:a copy` — mismo principio para el audio.
- `-bufsize 1000k` — buffer de salida que absorbe picos de latencia
  de red sin cortar la emisión.
- Las dos últimas líneas — FFmpeg envía el stream a los dos nodos
  simultáneamente. Cada nodo recibe el stream completo desde el
  primer fotograma para poder generar fragmentos HLS coherentes.
La salida de FFmpeg debe mostrar líneas similares a esta,
actualizándose continuamente:
 
```
frame=  142 fps= 25 q=-1.0 size=    1024kB time=00:00:05.68 bitrate=1476.5kbits/s
```
 
### 6.3 Ejecutar FFmpeg en segundo plano
 
Para que FFmpeg siga corriendo después de cerrar la terminal:
 
```bash
nohup ffmpeg \
  -re \
  -stream_loop -1 \
  -i ~/video_listo.mp4 \
  -c:v copy \
  -c:a copy \
  -bufsize 1000k \
  -max_muxing_queue_size 1024 \
  -f flv rtmp://10.0.4.195/live/stream \
  -f flv rtmp://10.0.4.166/live/stream \
  > ~/ffmpeg.log 2>&1 &
```
 
Para detener FFmpeg:
 
```bash
pkill ffmpeg
```
 
Para ver el log en tiempo real:
 
```bash
tail -f ~/ffmpeg.log
```
 
---
 
## 7. Correcciones Aplicadas
 
Durante el proceso de montaje se identificaron tres problemas
que degradaban significativamente el rendimiento del sistema.
Esta sección documenta cada problema, su causa y la solución
aplicada.
 
---
 
### Corrección 1 — HAProxy no distribuía el stream RTMP
 
**Problema**
 
La configuración inicial intentaba usar HAProxy para distribuir
tanto el tráfico HTTP como el RTMP entre los nodos. HAProxy solo
estaba configurado para escuchar en el puerto 80 (HTTP) y no
tenía ninguna configuración para el puerto 1935 (RTMP).
 
El resultado era que FFmpeg enviaba el stream RTMP al balanceador
pero ningún componente lo recibía ni lo distribuía a los nodos.
Solo uno de los nodos recibía el stream, o ninguno.
 
**Causa**
 
Los protocolos RTMP y HTTP son fundamentalmente distintos. RTMP
mantiene una conexión persistente y bidireccional, mientras que
HTTP funciona con peticiones y respuestas independientes. Mezclar
ambos en el mismo balanceador añade complejidad sin ninguna ventaja
real para este caso de uso.
 
**Solución**
 
Separar completamente las responsabilidades:
 
- FFmpeg envía el RTMP directamente a los dos nodos sin pasar
  por ningún balanceador. Al ser el emisor, FFmpeg puede abrir
  dos conexiones RTMP simultáneas de forma nativa.
- HAProxy gestiona exclusivamente el balanceo de las peticiones
  HTTP de los visitantes.
Esta separación además hace el sistema más robusto: un fallo
en HAProxy no afecta a la emisión, y un problema con FFmpeg
no afecta al servicio HTTP.
 
---
 
### Corrección 2 — Caché excesiva en el proxy de Visitantes
 
**Problema**
 
La configuración inicial del proxy Nginx en la subnet de Visitantes
incluía las siguientes directivas:
 
```nginx
proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=hls_cache:10m
                 max_size=1g inactive=5m use_temp_path=off;
proxy_cache hls_cache;
proxy_cache_valid 200 1m;
proxy_cache_lock on;
```
 
Esto cacheaba todas las respuestas del balanceador durante
1 minuto.
 
**Causa**
 
Los fragmentos HLS se regeneran cada 3 segundos. Con una caché
de 60 segundos, los visitantes recibían fragmentos con hasta
un minuto de antigüedad. El reproductor HLS.js no podía seguir
la secuencia del stream porque el fichero `.m3u8` que recibía
no correspondía con los fragmentos disponibles.
 
El fichero `.m3u8` es el índice del stream y se actualiza cada
vez que se genera un nuevo fragmento. Cachearlo durante cualquier
cantidad de tiempo mayor que la duración de un fragmento rompe
el mecanismo de HLS por diseño.
 
**Solución**
 
Eliminación completa de la caché en el proxy de Visitantes.
Sustitución por `proxy_buffering off`, que indica a Nginx que
reenvíe el contenido directamente sin almacenarlo:
 
```nginx
location /hls/ {
    proxy_pass http://10.0.4.242/;
    proxy_buffering off;
    add_header Cache-Control no-cache;
    add_header Access-Control-Allow-Origin *;
    proxy_connect_timeout 3s;
    proxy_read_timeout 10s;
}
```
 
---
 
### Corrección 3 — FFmpeg re-encodificando en tiempo real
 
**Problema**
 
El comando FFmpeg inicial no especificaba el codec de salida,
lo que provocaba que FFmpeg transcodificase el vídeo en tiempo
real: decodificaba cada fotograma del `.mp4` y lo volvía a
codificar en el formato adecuado para RTMP.
 
En una instancia t3.large, esta operación consumía entre el
80% y el 100% de la CPU, causando que FFmpeg no pudiera mantener
el ritmo de emisión de 25 fotogramas por segundo. El resultado
eran cortes frecuentes en el stream y degradación de calidad.
 
**Causa**
 
Sin el parámetro `-c:v copy`, FFmpeg asume que debe recodificar
el vídeo aplicando los parámetros de calidad especificados o
los valores por defecto. Para una emisión en bucle de vídeo
pregrabado, la recodificación en tiempo real no aporta ningún
beneficio y supone un coste computacional enorme.
 
**Solución**
 
Dos cambios combinados:
 
Primero, precodificar el vídeo en el PC del operador antes
de subirlo, preparándolo en el formato exacto que los nodos
necesitan (H.264 perfil baseline, nivel 3.0, con
`-movflags +faststart`).
 
Segundo, añadir `-c:v copy -c:a copy` al comando FFmpeg para
que simplemente reempaquete el vídeo ya preparado en el
contenedor RTMP sin recodificar. El consumo de CPU cae del
80-100% al 15-20%.
 
---
 
## 8. Verificación Final
Tras completar todas las fases y aplicar las correcciones,
verificar el sistema de extremo a extremo.
 
### 8.1 Verificar que los nodos reciben el stream
 
Desde cualquier máquina dentro de la VPC:
 
```bash
# Verificar HLS1
curl http://10.0.4.195/stream.m3u8
 
# Verificar HLS2
curl http://10.0.4.166/stream.m3u8
```
 
Ambos deben devolver el índice del stream con un formato similar a:
 
```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:3
#EXTINF:3.000,
stream-0.ts
#EXTINF:3.000,
stream-1.ts
#EXTINF:3.000,
stream-2.ts
```
 
Si alguno devuelve error 404, ese nodo no está recibiendo
el stream de FFmpeg.
 
### 8.2 Verificar el balanceador
 
```bash
curl http://10.0.4.242/stream.m3u8
```
 
Debe devolver el mismo resultado que los nodos. Si falla,
verificar que HAProxy está corriendo:
 
```bash
sudo docker ps
```
 
### 8.3 Verificar el proxy de Visitantes
 
Desde la máquina del portal de Visitantes:
 
```bash
curl http://localhost/hls/stream.m3u8
```
 
Debe devolver el índice del stream. Si falla verificar que
Nginx está activo:
 
```bash
sudo systemctl status nginx
```
 
### 8.4 Verificar el reproductor en el navegador
 
Desde un dispositivo en la subnet de Visitantes, abrir el
navegador y acceder a la IP del portal. El reproductor debe
arrancar y mostrar el vídeo en menos de 5 segundos.
 
### 8.5 Diagnóstico rápido de problemas
 
| Síntoma | Causa probable | Solución |
|---|---|---|
| `.m3u8` vacío en los nodos | FFmpeg no está corriendo | Relanzar FFmpeg |
| `.m3u8` vacío solo en un nodo | Un destino RTMP en FFmpeg falla | Verificar conectividad al nodo |
| HAProxy devuelve 503 | Ambos nodos sin stream | Relanzar FFmpeg |
| Vídeo no arranca en el navegador | HLS.js no puede descargar el `.m3u8` | Verificar proxy en Visitantes |
| Cortes frecuentes durante reproducción | CPU al límite en FFmpeg | Verificar que se usa `-c:v copy` |
| Vídeo con retraso creciente | Caché activa en el proxy | Verificar `proxy_buffering off` |