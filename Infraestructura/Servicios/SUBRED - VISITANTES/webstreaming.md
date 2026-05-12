# Flujo de Entrega HLS — Subred Visitantes
 
Documentación del recorrido que sigue una petición de red desde que un dispositivo conectado al WiFi público intenta reproducir el evento en directo, hasta que el fragmento de vídeo llega desde el backend.
 
---
 
## 1. Petición del cliente
 
El reproductor **Video.js**, embebido en el portal HTML, consume el streaming mediante **HLS (HTTP Live Streaming)**.
 
### Por qué Video.js y no el reproductor nativo del navegador
 
El protocolo HLS no tiene soporte nativo en la mayoría de navegadores de escritorio (Chrome, Firefox, Edge), a diferencia de un archivo `.mp4` convencional. Video.js actúa como motor intermedio: lee el formato HLS, descarga los fragmentos de vídeo y los inyecta al reproductor nativo del navegador en tiempo real.
 
### La ruta relativa: la decisión de diseño más relevante del frontend
 
La petición se lanza como un `GET` a la ruta relativa `/hls/stream.m3u8`. Esta es la línea más importante del frontend, y merece una explicación detenida.
 
Usar una ruta relativa en lugar de una IP absoluta (como `http://10.0.4.242/hls/...`) hace que el navegador del visitante dirija la petición al mismo servidor que le sirvió la página: el Nginx de la subred de visitantes. Esto tiene dos consecuencias directas para la arquitectura:
 
- **Oculta la topología interna** — el visitante nunca llega a ver las IPs de la subred de gestión (`10.0.4.0/24`).
- **Fuerza el uso del proxy inverso** — el cliente le pide el vídeo al Nginx de visitantes, que es el que hace el salto hacia HAProxy a través de la regla `location /hls/ { proxy_pass ... }` configurada en backend.
### El tipo MIME `application/x-mpegURL`
 
El atributo `type="application/x-mpegURL"` le indica a Video.js que lo que recibirá en esa ruta no es un vídeo, sino un archivo de texto: el manifiesto `stream.m3u8`. Con esa información, el reproductor sabe que debe abrir ese archivo, identificar qué fragmentos `.ts` están disponibles (los que residen en el `tmpfs` de los nodos HLS), descargarlos secuencialmente y quedarse a la escucha de actualizaciones del manifiesto para mantener el falso directo generado por FFmpeg.
 
---
 
## 2. Proxy inverso en la subred de visitantes (`10.0.3.0/24`)
 
Tanto la playlist (`.m3u8`) como los fragmentos de vídeo (`.ts`) aterrizan en la instancia **Nginx** (`t2.micro`) desplegada en la red de visitantes.
 
Nginx tiene dos responsabilidades aquí:
 
- **Validar el portal cautivo** — comprueba que el visitante haya aceptado los términos de uso antes de dejarle pasar.
- **Reenviar la petición** — actúa como proxy inverso hacia la IP correspondiente en la subred de gestión.
Un detalle importante: el reenvío se hace con `proxy_buffering off`. Para streaming en vivo esto no es opcional; sin esa directiva, Nginx acumularía fragmentos en disco antes de enviarlos, introduciendo latencia innecesaria. Con ella desactivada, los paquetes fluyen directamente hacia el cliente según llegan del backend.
 
---
 
## 3. Tránsito por el firewall perimetral
 
El tráfico entre visitantes y gestión no tiene un camino directo: debe pasar por la instancia Ubuntu que hace de **router NAT y firewall**.
 
La política por defecto en la cadena `FORWARD` es `DROP`, pero existe una regla explícita que autoriza el flujo desde `10.0.3.0/24` hacia `10.0.4.0/24` en los puertos 80 y 8000.
 
Lo relevante en términos de seguridad: este diseño garantiza que ninguna petición originada en la subred de visitantes pueda llegar a la **subred SOC** (`10.0.6.0/24`). La segmentación no es solo una capa de red, sino un requisito de seguridad del recinto.
 
---
 
## 4. Balanceo de carga (`10.0.4.242`)
 
La petición llega a **HAProxy**, que se encarga de distribuirla entre los nodos de streaming disponibles.
 
El algoritmo configurado es `leastconn`: en lugar de repartir peticiones en round-robin, HAProxy consulta cuántas conexiones activas tiene cada nodo y envía la nueva al menos cargado. Esto resulta especialmente útil con fragmentos HLS, cuya duración de descarga puede variar según el tamaño del segmento y las condiciones de red.
 
HAProxy también realiza *health checks* activos: solo considera disponible un nodo si `stream.m3u8` responde correctamente. Si el streaming del evento se interrumpe en un nodo, ese nodo sale de rotación de forma automática.
 
---
 
## 5. Entrega desde RAM (`10.0.4.195` / `10.0.4.166`)
 
El fragmento es finalmente servido por uno de los dos nodos HLS, cada uno ejecutando **nginx-rtmp dentro de un contenedor Docker**.
 
El punto clave de este nivel es que los archivos no se leen desde disco. El nodo monta un volumen `tmpfs` de 300 MB en memoria RAM, y es desde ahí desde donde sirve tanto los `.m3u8` como los `.ts`. El objetivo es eliminar cualquier cuello de botella de I/O de disco en escenarios de alta concurrencia, como las pruebas de carga masiva realizadas con iPerf3.
 
La respuesta recorre la ruta inversa:
 
```
Nodo HLS → HAProxy → Firewall → Nginx Visitantes → Navegador
```
 
Video.js recibe los fragmentos en orden y ensambla el flujo en tiempo real.