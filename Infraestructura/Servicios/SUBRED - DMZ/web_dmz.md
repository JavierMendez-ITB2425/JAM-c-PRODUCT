# Configuración de Infraestructura — Máquina DMZ
 
---
 
## Máquina DMZ — Servidor Web Nginx
 
### Acceso a la instancia
 
El acceso a la máquina DMZ no es directo desde el exterior: al estar en una subred privada, es necesario saltar primero por la instancia firewall.
 
**Paso 1 — Descargar la clave y ajustar permisos**
 
Una vez descargada la clave `labsuser_jamv2.pem`, se restringe su acceso para que SSH la acepte:
 
```bash
chmod 400 labsuser_jamv2.pem
```
 
**Paso 2 — Conexión SSH al firewall (salto intermedio)**
 
```bash
ssh -i labsuser_jamv2.pem ubuntu@44.209.162.147
```
 
La primera vez, SSH advertirá que el fingerprint del host no es conocido y pedirá confirmación. Se acepta y el sistema añade la IP a `~/.ssh/known_hosts` automáticamente.
 
**Paso 3 — Conexión SSH a la máquina DMZ**
 
Desde el firewall, se salta a la instancia web interna:
 
```bash
ssh -i labsuser_jamv2.pem ubuntu@10.0.5.50
```
 
El prompt confirma el acceso: `ubuntu@Web-DMZ:~$`. La IP interna de la máquina es `10.0.5.50` (interfaz `eth0`).
 
---
 
### Instalación y arranque de Nginx
 
**Paso 4 — Instalación**
 
```bash
sudo apt install nginx -y
```
 
Si el paquete ya está instalado, `apt` lo indica sin reinstalarlo (`0 upgraded, 0 newly installed`). En este caso la versión presente era `nginx 1.18.0-6ubuntu14.10`.
 
**Paso 5 — Arranque y verificación del servicio**
 
```bash
sudo systemctl start nginx
sudo systemctl status nginx
```
 
La salida esperada muestra el servicio en estado `active (running)`. El proceso maestro (`PID 455`) gestiona un worker que es el que atiende las peticiones HTTP.
 
---
 
### Apertura de puertos en el firewall local (UFW)
 
**Paso 6 — Permitir tráfico web**
 
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```
 
**Paso 7 — Verificar el estado de UFW**
 
```bash
sudo ufw status
```
 
El resultado correcto muestra `Status: active` con las siguientes reglas activas:
 
| Puerto | Acción | Origen |
|--------|--------|--------|
| 22/tcp | ALLOW | Anywhere |
| 80/tcp | ALLOW | Anywhere |
| 443/tcp | ALLOW | Anywhere |
 
Las mismas reglas aplican también para IPv6 (`v6`).
 
---
 
### Despliegue del sitio web
 
**Paso 8 — Subir el `index.html` personalizado**
 
Se elimina la página por defecto de Nginx y se sustituye por el HTML del proyecto:
 
```bash
sudo rm /var/www/html/index.nginx-debian.html
sudo nano /var/www/html/index.html
```
 
El archivo corresponde al portal **JAM'c Elite — Ticketing Profesional**. Se puede verificar su contenido con:
 
```bash
cat index.html
```
 
Una primera comprobación accediendo a la IP pública (`54.80.156.229`) confirma que el servidor responde, aunque en este punto el streaming HLS aún no está configurado (el reproductor devuelve un error de media).
 
**Paso 9 — Ajustar permisos sobre el directorio web**
 
```bash
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```
 
Esto asegura que el proceso `nginx` (que corre como `www-data`) puede leer y servir los archivos correctamente.
 
**Paso 10 — Reiniciar Nginx para aplicar los cambios**
 
```bash
sudo systemctl restart nginx
```
 
En este punto, acceder a `54.80.156.229` desde el navegador ya muestra el portal completo con el navbar y el hero de JAM'c Elite.
 
---
 
### Dominio dinámico con DuckDNS
 
**Paso 11 — Registrar el subdominio**
 
Se crea el subdominio `jamcelitee` en [duckdns.org](https://www.duckdns.org), apuntando a la IP pública `54.80.156.229`. La plataforma confirma el registro:
 
```
success: domain jamcelitee.duckdns.org added to your account
```
 
A partir de aquí, el sitio es accesible por nombre en lugar de por IP.
 
---
 
### Virtual Host en Nginx
 
**Paso 12 — Crear el fichero de configuración del sitio**
 
```bash
sudo nano /etc/nginx/sites-available/jamc
```
 
Contenido del virtual host:
 
```nginx
server {
    listen 80;
    server_name jamcelitee.duckdns.org www.jamcelitee.duckdns.org;
 
    root /var/www/html;
    index index.html;
 
    location / {
        try_files $uri $uri/ =404;
    }
 
    access_log /var/log/nginx/jamcelitee_access.log;
    error_log  /var/log/nginx/jamcelitee_error.log;
}
```
 
Los logs separados por sitio facilitan el diagnóstico en entornos con múltiples dominios.
 
**Paso 13 — Activar el sitio**
 
```bash
sudo ln -s /etc/nginx/sites-available/jamcelitee /etc/nginx/sites-enabled/
```
 
**Paso 14 — Comprobar la sintaxis y recargar**
 
```bash
sudo nginx -t
sudo systemctl reload nginx
```
 
Si la configuración es correcta, `nginx -t` devuelve:
 
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```
 
---
 
### HTTPS con Certbot y Let's Encrypt
 
**Paso 15 — Emitir y desplegar el certificado**
 
```bash
sudo certbot --nginx -d jamcelitee.duckdns.org -d www.jamcelitee.duckdns.org
```
 
El proceso solicita una dirección de correo para notificaciones de renovación y pide aceptar los términos del servicio. Certbot se encarga de validar el dominio, emitir el certificado y modificar automáticamente la configuración de Nginx para activar HTTPS.
 
Resultado:
 
```
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/jamcelitee.duckdns.org/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/jamcelitee.duckdns.org/privkey.pem
This certificate expires on 2026-08-10.
```
 
Certbot además configura una tarea programada para renovar el certificado automáticamente antes de su vencimiento.
 
**Paso 16 — Activar la redirección HTTP → HTTPS**
 
```bash
sudo certbot --nginx --redirect
```
 
Se seleccionan los dos dominios (`jamcelitee.duckdns.org` y `www.jamcelitee.duckdns.org`) y Certbot añade la redirección 301 a la configuración de Nginx.
 
**Paso 17 — Comprobación final**
 
```bash
curl -I https://jamcelitee.duckdns.org
```
 
Respuesta esperada:
 
```
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
Date: Tue, 12 May 2026 14:55:25 GMT
Content-Type: text/html
Content-Length: 97784
Connection: keep-alive
```
 
El código `200 OK` con `Content-Type: text/html` confirma que el servidor está sirviendo el portal correctamente sobre HTTPS.
 
---