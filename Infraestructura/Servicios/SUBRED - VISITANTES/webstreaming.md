# Flujo de Entrega HLS — Subred Visitantes
 
Esta sección documenta el recorrido completo de una petición
de streaming desde que el dispositivo de un visitante solicita
el vídeo hasta que recibe el primer fragmento reproducible.
Entender este flujo es clave para diagnosticar cualquier
problema de rendimiento o conectividad en el servicio.
 
---
 
## El Punto de Partida — El Reproductor en el Navegador
 
Cuando un visitante abre el portal desde
su móvil o portátil, el navegador carga una página HTML que
incluye el reproductor Video.js configurado para HLS.
 
La primera petición que hace el reproductor es siempre al
fichero de índice del stream:
 
```
GET /hls/stream.m3u8
```
 
Al ser una ruta relativa, la petición va dirigida al mismo
servidor que sirvió la página — el portal Nginx en la subnet
de Visitantes. El visitante no sabe, ni necesita saber, que
el vídeo viene de otra subnet completamente diferente.
 
---
 
## Primera Parada — Nginx en la Subnet de Visitantes
 
El portal Nginx recibe la petición y hace dos cosas antes
de reenviarla al backend.
 
La primera es comprobar que el visitante ha pasado por el
portal cautivo y ha aceptado los términos de uso de la red
WiFi. Una petición que llegue sin esa validación no continúa.
 
La segunda es actuar como proxy inverso — reenvía la petición
hacia el balanceador en la subnet de Gestión (10.0.4.242).
Para el visitante, todo ocurre de forma transparente: su
navegador habla con Nginx y Nginx habla con el backend.
 
La directiva que marca la diferencia aquí es `proxy_buffering off`.
Sin ella, Nginx descargaría cada fragmento de vídeo completo
antes de empezar a enviarlo al cliente. En un stream en vivo
con fragmentos que se regeneran cada tres segundos, ese buffer
añade latencia acumulada que acaba degradando la experiencia
hasta hacerla inutilizable. Con `proxy_buffering off`, los
bytes del fragmento viajan directamente del backend al navegador
conforme llegan, sin escalas intermedias.
 
---
 
## Segunda Parada — El Firewall
 
El tráfico entre la subnet de Visitantes (10.0.3.0/24) y la
subnet de Gestión (10.0.4.0/24) no tiene un camino directo.
Toda comunicación entre subredes pasa por la instancia Ubuntu
que actúa como router NAT y firewall perimetral.
 
Cuando el paquete llega al firewall, iptables evalúa si puede
continuar. La cadena FORWARD tiene política por defecto DROP,
lo que significa que cualquier tráfico que no esté explícitamente
autorizado se descarta sin respuesta.
 
Para el streaming existe una regla concreta que permite el paso:
 
```
origen 10.0.3.0/24 → destino 10.0.4.0/24, puertos 80 y 8000: ACCEPT
```
 
El tráfico de Visitantes hacia SOC (10.0.6.0/24), en cambio,
tiene su propia regla DROP. Un visitante no puede alcanzar
el SOC aunque lo intente — el paquete desaparece en el firewall
sin dejar rastro en el destino, aunque sí en los logs del
propio firewall, donde Wazuh puede detectar el intento.
 
---
 
## Tercera Parada — HAProxy en el Balanceador
 
La petición llega al balanceador (10.0.4.242), donde HAProxy
escucha en el puerto 80 y decide a qué nodo HLS enviarla.
 
El algoritmo configurado es `leastconn`. A diferencia de
round-robin, que reparte peticiones de forma ciega y alternada,
`leastconn` consulta cuántas conexiones activas tiene cada nodo
en ese momento y envía la nueva petición al que tenga menos.
Para HLS esto importa: los fragmentos de vídeo no siempre tardan
lo mismo en transferirse, y un nodo que acumula varias
transferencias lentas simultáneas puede convertirse en un cuello
de botella si el balanceador sigue mandándole peticiones sin
mirar su carga real.
 
Antes de enviar visitantes a un nodo, HAProxy verifica que
el stream esté realmente activo. Cada dos segundos hace una
petición al fichero `stream.m3u8` de cada nodo. Si el fichero
no responde o devuelve error, HAProxy saca ese nodo del pool
de forma automática y redirige todo el tráfico al que sigue
funcionando. En cuanto el nodo se recupera, vuelve a entrar
en rotación sin intervención manual.
 
---
 
## Destino Final — Los Nodos HLS
 
La petición llega a uno de los dos nodos de streaming
(10.0.4.195 o 10.0.4.166), donde corre nginx-rtmp dentro
de un contenedor Docker.
 
Lo primero que hace nginx-rtmp es buscar el fichero solicitado
en `/tmp/hls`. Esta ruta no corresponde al disco de la instancia
sino a un sistema de ficheros montado en la memoria RAM de
la máquina mediante `tmpfs`. Los 300MB de RAM reservados para
este propósito alojan los fragmentos `.ts` y el índice `.m3u8`
que nginx-rtmp va generando y reemplazando continuamente a
medida que FFmpeg le envía el stream.
 
La razón de usar RAM en lugar de disco es una cuestión de
velocidad de escritura y número de operaciones. Cada tres
segundos el nodo crea un fragmento nuevo, actualiza el índice
y elimina el fragmento más antiguo. A lo largo de una sesión
de streaming de varias horas, el número de operaciones de
escritura sobre el mismo espacio de almacenamiento es enorme.
En disco, esas operaciones generan latencia e I/O que en una
instancia de tamaño limitado acaban afectando al rendimiento
general. En RAM, la operación es instantánea.
 
---
 
## El Viaje de Vuelta
 
Una vez el nodo tiene el fragmento listo, la respuesta recorre
el mismo camino en sentido inverso:
 
```
Nodo HLS
   → HAProxy (confirma el estado de la conexión)
      → Firewall (el tráfico de vuelta está autorizado
                  por la regla ESTABLISHED/RELATED)
         → Nginx Visitantes (reenvía al cliente sin buffer)
            → Navegador del visitante
```
 
El reproductor Video.js ensambla los fragmentos en el orden
indicado por el fichero `.m3u8` y los reproduce de forma
continua. Mientras el visitante ve los primeros segundos,
el reproductor está descargando en segundo plano los
fragmentos siguientes para mantener el buffer lleno y evitar
interrupciones ante cualquier variación puntual en la red.
 