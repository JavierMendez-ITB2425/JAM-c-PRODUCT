# Guía de Administración — Arranque del Servicio de Streaming
 
## Antes de Empezar
 
Verifica que tienes acceso a:
 
- La clave SSH `labsuser_jam.pem`
- La IP pública del firewall
- El archivo de vídeo precodificado `video_listo.mp4`
---
 
## IPs de las Máquinas
 
| Máquina | IP Privada |
|---|---|
| Balanceador | 10.0.4.242 |
| HLS1 | 10.0.4.195 |
| HLS2 | 10.0.4.166 |
 
---
 
## Paso 1 — Añadir la clave SSH al agente
 
```bash
ssh-add ~/Documents/labsuser_jam.pem
```
 
---
 
## Paso 2 — Arrancar HLS1
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.195
```
 
```bash
cd ~/streaming && sudo docker-compose up -d
```
 
Verificar que está corriendo:
 
```bash
sudo docker ps
```
 
Debe aparecer el contenedor `nginx-origen` con estado `Up`.
Salir de la máquina:
 
```bash
exit
```
 
---
 
## Paso 3 — Arrancar HLS2
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.166
```
 
```bash
cd ~/streaming && sudo docker-compose up -d
```
 
Verificar que está corriendo:
 
```bash
sudo docker ps
```
 
Debe aparecer el contenedor `nodo-hls` con estado `Up`.
Salir de la máquina:
 
```bash
exit
```
 
---
 
## Paso 4 — Arrancar el Balanceador
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.242
```
 
```bash
cd ~/balanceador && sudo docker-compose up -d
```
 
Verificar que HAProxy está corriendo:
 
```bash
sudo docker ps
```
 
Debe aparecer el contenedor `haproxy-balanceador` con estado `Up`.
 
---
 
## Paso 5 — Subir el vídeo (solo si no está ya en la máquina)
 
Desde tu PC local, ejecutar este comando. Si el vídeo ya está
en el balanceador de una sesión anterior, saltar al Paso 6.
 
```bash
scp -i labsuser_jam.pem \
    -o "ProxyJump ubuntu@<IP_FIREWALL>" \
    /ruta/local/video_listo.mp4 \
    ubuntu@10.0.4.242:~/video_listo.mp4
```
 
---
 
## Paso 6 — Lanzar FFmpeg
 
Desde la sesión abierta en el balanceador del Paso 4:
 
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
 
Verificar que FFmpeg está emitiendo:
 
```bash
tail -f ~/ffmpeg.log
```
 
Debes ver líneas actualizándose con `fps=25`. Pulsar `Ctrl+C`
para salir del log sin detener FFmpeg.
 
---
 
## Paso 7 — Verificar el Stream
 
Desde el balanceador, comprobar que los dos nodos están
sirviendo el stream:
 
```bash
curl http://10.0.4.195/stream.m3u8
curl http://10.0.4.166/stream.m3u8
```
 
Ambos deben devolver el índice del stream. Si uno devuelve
error, ver la sección de Resolución de Problemas.
 
---
 
## El Streaming ya está Activo
 
Los visitantes conectados al WiFi del Palau pueden acceder
al stream abriendo el navegador y entrando en el portal.
 
---
 
## Detener el Servicio
 
### Detener FFmpeg
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.242
pkill ffmpeg
```
 
### Detener los nodos HLS
 
```bash
# En HLS1
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.195
cd ~/streaming && sudo docker-compose down
 
# En HLS2
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.166
cd ~/streaming && sudo docker-compose down
```
 
### Detener HAProxy
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.242
cd ~/balanceador && sudo docker-compose down
```
 
---
 
## Resolución de Problemas
 
**El stream no aparece en uno de los nodos**
 
FFmpeg no está llegando a ese nodo. Verificar que el nodo
tiene Docker corriendo y que el contenedor está activo:
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.19X
sudo docker ps
```
 
Si el contenedor no aparece, arrancarlo de nuevo:
 
```bash
cd ~/streaming && sudo docker-compose up -d
```
 
Después reiniciar FFmpeg en el balanceador:
 
```bash
pkill ffmpeg
# Volver a ejecutar el comando del Paso 6
```
 
---
 
**HAProxy devuelve error 503**
 
Ninguno de los dos nodos está respondiendo correctamente.
Verificar que los contenedores están activos en HLS1 y HLS2
y que FFmpeg está emitiendo. Revisar el log:
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.242
tail -f ~/ffmpeg.log
```
 
---
 
**FFmpeg se ha detenido solo**
 
Revisar el log para identificar el error:
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@10.0.4.242
cat ~/ffmpeg.log | tail -50
```
 
El error más común es que el archivo `video_listo.mp4` no está
en la ruta esperada. Verificar:
 
```bash
ls -lh ~/video_listo.mp4
```
 
Si no existe, repetir el Paso 5.
 
---
 
**Los visitantes ven el vídeo con cortes**
 
Verificar que el portal de Visitantes tiene Nginx activo:
 
```bash
ssh -A -J ubuntu@<IP_FIREWALL> ubuntu@<IP_PORTAL>
sudo systemctl status nginx
```
 
Si está caído, arrancarlo:
 
```bash
sudo systemctl start nginx
```