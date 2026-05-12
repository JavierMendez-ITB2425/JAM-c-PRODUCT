# Documentación del Sistema de Streaming — Concepto

## Índice

1. [Visión General](#1-visión-general)
2. [Arquitectura y Componentes](#2-arquitectura-y-componentes)
3. [Los Protocolos — RTMP y HLS](#3-los-protocolos--rtmp-y-hls)
4. [El Rol de Cada Máquina](#4-el-rol-de-cada-máquina)
5. [La RAM como Sistema de Ficheros](#5-la-ram-como-sistema-de-ficheros)
6. [El Balanceador de Carga](#6-el-balanceador-de-carga)
7. [Flujo Completo de Extremo a Extremo](#7-flujo-completo-de-extremo-a-extremo)
8. [El Portal de Visitantes](#8-el-portal-de-visitantes)
9. [Precodificación del Vídeo](#9-precodificación-del-vídeo)
10. [Problemas Encontrados y Soluciones](#10-problemas-encontrados-y-soluciones)
11. [Limitaciones y Escalabilidad Real](#11-limitaciones-y-escalabilidad-real)

---

## 1. Visión General

El sistema de streaming permite a los visitantes conectados a la red WiFi del recinto acceder a las repeticiones de los mejores momentos del evento en curso directamente desde su navegador o dispositivo móvil, sin necesidad de instalar ninguna aplicación.

El diseño replica conceptualmente la infraestructura que operadores como Telefónica despliegan en recintos de gran aforo, adaptando los componentes a un entorno de laboratorio en AWS. La diferencia con un despliegue real no es el diseño sino la escala.

El sistema se divide en tres zonas claramente diferenciadas dentro de la **Subnet de Gestión (10.0.4.0/24)**:

- Un **emisor** que toma el vídeo pregrabado y lo inyecta en la red
- Dos **nodos de procesamiento** que convierten ese vídeo a un formato reproducible en cualquier dispositivo
- Un **balanceador** que distribuye la carga entre los nodos y sirve el contenido a los visitantes

---

## 2. Arquitectura y Componentes

### Diagrama de la arquitectura

```
[Vídeo pregrabado .mp4]
         |
         | RTMP (puerto 1935)
         ↓
[BALANCEADOR 10.0.4.242]
    FFmpeg + HAProxy
         |
    ┌────┴────┐
    | RTMP    | RTMP
    ↓         ↓
[HLS1]     [HLS2]
10.0.4.195  10.0.4.166
nginx-rtmp  nginx-rtmp
tmpfs RAM   tmpfs RAM
    |         |
    └────┬────┘
         | HTTP (puerto 80)
         ↓
[BALANCEADOR — HAProxy]
         |
         | HTTP
         ↓
[PORTAL VISITANTES 10.0.3.x]
    Nginx + HLS.js
         |
         ↓
[Dispositivo del visitante]
```

### Componentes por máquina

| Máquina | IP | Software | Función |
|---|---|---|---|
| Balanceador | 10.0.4.242 | FFmpeg + HAProxy | Emite el vídeo e iguala la carga |
| HLS1 | 10.0.4.195 | nginx-rtmp + tmpfs | Procesa y sirve el stream |
| HLS2 | 10.0.4.166 | nginx-rtmp + tmpfs | Procesa y sirve el stream |
| Portal Visitantes | 10.0.3.x | Nginx + HLS.js | Web con el reproductor |

---

## 3. Los Protocolos — RTMP y HLS

Entender por qué se usan dos protocolos distintos es fundamental para comprender el sistema.

### RTMP — Real-Time Messaging Protocol

RTMP es el protocolo que transporta el vídeo desde FFmpeg hasta los nodos de streaming. Fue diseñado originalmente por Macromedia (luego Adobe) para streaming en tiempo real y se ha convertido en el estándar universal para la **ingesta de vídeo** — es decir, para enviar vídeo desde una fuente hacia un servidor.

Sus características principales en este contexto son:

**Baja latencia en la ingesta.** RTMP mantiene una conexión persistente entre FFmpeg y cada nodo, lo que elimina el overhead de establecer una nueva conexión para cada dato enviado. El vídeo fluye de forma continua sin interrupciones.

**Fiabilidad.** RTMP corre sobre TCP, lo que garantiza que ningún paquete se pierde en el camino. Para vídeo en directo, perder un paquete significa un artefacto visual visible para el usuario.

**Compatibilidad universal.** Todos los servidores de streaming profesionales — desde YouTube Live hasta Twitch — aceptan RTMP como protocolo de ingesta. Que el proyecto lo use no es una decisión arbitraria sino el estándar del sector.

Sin embargo, RTMP tiene un problema importante para la distribución al cliente final: **los navegadores modernos no pueden reproducir RTMP directamente**. Es ahí donde entra HLS.

### HLS — HTTP Live Streaming

HLS fue desarrollado por Apple y se ha convertido en el estándar universal para la **entrega de vídeo** al usuario final. A diferencia de RTMP, funciona sobre HTTP normal, lo que significa que cualquier navegador, móvil o smart TV puede reproducirlo sin instalar nada.

El funcionamiento de HLS es radicalmente distinto a RTMP. En lugar de un stream continuo, HLS divide el vídeo en pequeños fragmentos de pocos segundos y genera un fichero índice que los enumera. El reproductor del cliente descarga ese índice, descarga los fragmentos en orden y los reproduce secuencialmente, dando la sensación de un vídeo continuo.

En el proyecto, cada nodo nginx-rtmp hace exactamente esta conversión:

1. Recibe el stream RTMP continuo de FFmpeg
2. Cada 3 segundos corta el vídeo y genera un fichero `.ts` (el fragmento)
3. Actualiza el fichero `.m3u8` (el índice) añadiendo el nuevo fragmento y eliminando el más antiguo

El resultado es que en la carpeta `/tmp/hls` de cada nodo siempre hay aproximadamente 4 fragmentos disponibles — los últimos 12 segundos del stream — listos para ser descargados por los visitantes.

### Por qué dos protocolos y no uno solo

La razón es técnica y práctica al mismo tiempo. RTMP es eficiente para la ingesta porque mantiene una conexión persistente, pero esa misma persistencia lo hace inadecuado para distribuir a miles de usuarios simultáneos — cada usuario necesitaría su propia conexión permanente con el servidor.

HLS resuelve esto de forma elegante: como usa HTTP estándar, cada petición de fragmento es independiente. El servidor no necesita mantener ninguna conexión abierta. Un visitante que pausa el vídeo simplemente deja de hacer peticiones HTTP — el servidor ni siquiera lo nota.

---

## 4. El Rol de Cada Máquina

### El Balanceador (10.0.4.242)

El balanceador es la pieza central del sistema y tiene dos funciones completamente separadas que operan en paralelo.

**Primera función — Emisión con FFmpeg**

FFmpeg es la herramienta que toma el archivo `.mp4` pregrabado y lo convierte en un stream RTMP en tiempo real. La clave de la configuración es que FFmpeg envía el stream **a los dos nodos simultáneamente**, no de forma alternada.

Esto es crítico: cada nodo necesita el stream completo desde el primer fotograma para generar una secuencia de fragmentos HLS coherente. Si FFmpeg solo enviara a un nodo, el otro no tendría nada que servir.

El parámetro `-c:v copy` es el más importante del comando FFmpeg. Le indica que **no recodifique** el vídeo — simplemente lo reempaqueta en formato RTMP tal como está. Sin este parámetro, FFmpeg tendría que descomprimir y recomprimir cada fotograma en tiempo real, lo que consumiría el 100% de la CPU del balanceador y causaría cortes constantes.

**Segunda función — Balanceo HTTP con HAProxy**

HAProxy recibe las peticiones HTTP de los visitantes que quieren ver el stream y las distribuye entre HLS1 y HLS2. Utiliza el algoritmo `leastconn` — cada nueva petición va al nodo con menos conexiones activas en ese momento, lo que garantiza una distribución equitativa incluso cuando los visitantes se conectan y desconectan de forma irregular.

HAProxy también realiza comprobaciones de salud cada 2 segundos, solicitando el fichero `.m3u8` a cada nodo. Si un nodo no responde o responde con error, HAProxy lo saca del pool automáticamente y envía todo el tráfico al nodo que sigue funcionando. Cuando el nodo se recupera, HAProxy lo reincorpora sin intervención manual.

### Los Nodos HLS1 y HLS2 (10.0.4.195 y 10.0.4.166)

Ambos nodos son idénticos en configuración y función. Cada uno ejecuta nginx-rtmp dentro de un contenedor Docker y realiza exactamente el mismo trabajo de forma independiente.

El módulo RTMP de nginx escucha en el puerto 1935 y, en cuanto recibe el stream de FFmpeg, empieza a generar fragmentos HLS en la carpeta `/tmp/hls`. El módulo HTTP de nginx escucha en el puerto 80 y sirve esos fragmentos cuando los visitantes los solicitan.

La configuración `allow publish 10.0.4.242` restringe quién puede enviar streams al nodo — solo el balanceador puede hacerlo. Esto evita que alguien en la red interna pudiera inyectar contenido no autorizado.

---

## 5. La RAM como Sistema de Ficheros

Una de las decisiones de optimización más importantes del proyecto es usar **tmpfs** para almacenar los fragmentos HLS en lugar del disco duro de la instancia.

### Qué es tmpfs

tmpfs es un sistema de ficheros que vive completamente en la memoria RAM. Para el sistema operativo y las aplicaciones parece una carpeta normal — nginx-rtmp escribe en ella exactamente igual que lo haría en disco. La diferencia es que las operaciones de lectura y escritura se realizan a velocidades de RAM (varios GB/s) en lugar de velocidades de disco (cientos de MB/s).

### Por qué es importante para HLS

El sistema de streaming genera y elimina ficheros constantemente. Cada 3 segundos se crea un nuevo fragmento `.ts` y se elimina el más antiguo. Con fragmentos de aproximadamente 200KB, el sistema realiza varias operaciones de escritura por segundo de forma indefinida.

En disco, cada una de estas operaciones implica acceder al hardware de almacenamiento, lo que añade latencia y carga de I/O que puede saturar una instancia pequeña. En RAM, la operación es instantánea y sin ningún impacto en el resto del sistema.

En Docker, tmpfs se declara directamente en el `docker-compose.yml` con un tamaño máximo de 300MB. Los fragmentos HLS del stream en cualquier momento dado ocupan menos de 10MB — los 300MB son un margen generoso que garantiza que nunca habrá problemas de espacio.

### Lo que se pierde con tmpfs

Al ser RAM, el contenido desaparece cuando el contenedor se detiene o la instancia se reinicia. Esto no es un problema para este caso de uso porque los fragmentos HLS son contenido efímero por diseño — un fragmento generado hace 30 segundos ya no es útil para nadie.

---

## 6. El Balanceador de Carga

### Por qué HAProxy y no Nginx

La elección de HAProxy para el balanceo HTTP responde a sus características técnicas específicas para este caso de uso.

HAProxy fue diseñado exclusivamente para balanceo de carga y proxy, mientras que Nginx es un servidor web que también puede balancear. Para cargas de streaming con muchas conexiones simultáneas cortas (cada fragmento HLS es una petición HTTP independiente), HAProxy gestiona la concurrencia de forma más eficiente.

El parámetro `nbthread 2` en la configuración de HAProxy le indica que use los dos núcleos de CPU disponibles en la instancia, distribuyendo el trabajo entre ambos.

### El algoritmo leastconn

`leastconn` es especialmente adecuado para streaming HLS porque las peticiones no tienen todas la misma duración. Un fragmento `.ts` de alta calidad puede tardar más en transferirse que uno de baja calidad, y si un nodo acumula varias transferencias lentas simultáneas, `leastconn` automáticamente desvía las nuevas peticiones al nodo más libre.

El algoritmo alternativo, `roundrobin`, distribuye peticiones de forma estrictamente alternada sin considerar la carga real de cada nodo, lo que puede generar desequilibrios en escenarios de streaming variable.

### Health checks activos

La configuración `option httpchk GET /stream.m3u8` hace que HAProxy no solo compruebe si el nodo está respondiendo, sino que compruebe específicamente si el stream existe y está activo. Un nodo puede estar funcionando perfectamente pero sin recibir el stream de FFmpeg, en cuyo caso respondería con error 404 al pedir el `.m3u8` y HAProxy lo sacaría del pool automáticamente.

---

## 7. Flujo Completo de Extremo a Extremo

Para entender el sistema en su totalidad, este es el recorrido completo desde el fichero de vídeo hasta los ojos del visitante:

**Paso 1 — Preparación del contenido**

Antes de cualquier emisión, el fichero `.mp4` con los mejores momentos del evento se precodifica en el PC del operador técnico. Este proceso, que puede tardar unos minutos, prepara el vídeo en un formato óptimo que los nodos podrán reempaquetar sin esfuerzo computacional. El resultado se almacena en el balanceador.

**Paso 2 — Ingesta RTMP**

El operador técnico lanza FFmpeg en el balanceador. FFmpeg lee el fichero `.mp4` en bucle continuo — cuando llega al final, vuelve a empezar desde el principio — y establece dos conexiones RTMP simultáneas, una con HLS1 y otra con HLS2. Ambos nodos empiezan a recibir exactamente el mismo stream.

**Paso 3 — Generación de fragmentos HLS**

En cada nodo, nginx-rtmp recibe el stream RTMP y cada 3 segundos genera un fragmento `.ts` que escribe en la RAM (tmpfs). Simultáneamente actualiza el fichero `stream.m3u8` para reflejar los nuevos fragmentos disponibles y eliminar los más antiguos.

**Paso 4 — Conexión del visitante**

El visitante conectado al WiFi del Palau abre su navegador. La subnet de Visitantes le sirve la página del portal, que incluye el reproductor HLS.js configurado para mantener un buffer amplio de contenido.

**Paso 5 — Descarga del índice**

HLS.js realiza su primera petición HTTP al balanceador solicitando `stream.m3u8`. HAProxy recibe la petición y la envía a uno de los dos nodos. El nodo responde con el índice del stream, que contiene la lista de los fragmentos disponibles.

**Paso 6 — Reproducción**

HLS.js descarga los fragmentos en orden y empieza a reproducir el vídeo. Mientras el visitante ve los primeros segundos, HLS.js está descargando fragmentos futuros para mantener un buffer de 24 segundos. Este buffer es la razón por la que pequeñas interrupciones de red no afectan a la experiencia del usuario.

**Paso 7 — Actualización continua**

Cada pocos segundos HLS.js vuelve a pedir el fichero `.m3u8` para obtener la lista de los fragmentos más recientes. Este ciclo se repite indefinidamente mientras el visitante tenga el reproductor abierto.

---

## 8. El Portal de Visitantes

El portal de visitantes es la interfaz que ve el usuario final. Técnicamente es una página HTML servida por Nginx en la subnet de Visitantes que actúa como proxy inverso hacia el balanceador de Gestión.

### El proxy inverso en Nginx

Cuando el visitante pide un fragmento HLS, la petición va a Nginx en la subnet de Visitantes, que la reenvía al balanceador en Gestión. El visitante nunca sabe que el contenido viene de otra subnet — desde su perspectiva, todo viene del portal.

La configuración `proxy_buffering off` es importante: le indica a Nginx que no almacene el fragmento en memoria antes de enviarlo al cliente, sino que lo reenvíe byte a byte conforme lo recibe. Para streaming en vivo esto es lo correcto — añadir otro nivel de buffering solo introduce latencia adicional innecesaria.

### HLS.js y la configuración del reproductor

HLS.js es una librería JavaScript que implementa el protocolo HLS en el navegador. Sin ella, solo Safari (que tiene soporte HLS nativo) podría reproducir el stream. Con HLS.js, cualquier navegador moderno puede hacerlo.

Los parámetros más relevantes de la configuración son:

**`maxBufferLength: 24`** — HLS.js mantiene 24 segundos de vídeo descargado y listo en memoria. Si la red se interrumpe durante menos de 24 segundos, el usuario no nota nada porque el reproductor consume el buffer acumulado.

**`liveSyncDurationCount: 4`** — controla a cuántos fragmentos del final del stream vivo se sitúa el reproductor. Con fragmentos de 3 segundos y un valor de 4, el visitante ve el contenido con aproximadamente 12 segundos de retraso respecto a la emisión. Este pequeño retraso es el precio del buffering que evita los cortes.

**`fragLoadingMaxRetry: 6`** — si un fragmento no se descarga correctamente, HLS.js lo reintenta hasta 6 veces antes de considerar el stream roto. Esto hace al reproductor resiliente frente a pérdidas de paquetes puntuales en la red WiFi del recinto.

---

## 9. Precodificación del Vídeo

La precodificación es el proceso previo a la emisión que tiene el mayor impacto en el rendimiento del sistema.

### El problema de transcodificar en tiempo real

Sin precodificación, FFmpeg tendría que decodificar cada fotograma del `.mp4` original y recodificarlo en el formato adecuado para RTMP en tiempo real. En una instancia con recursos limitados, esta operación puede consumir el 100% de la CPU, causando que FFmpeg no pueda mantener el ritmo de emisión y el stream se degrade o corte.

### La solución — `-c:v copy`

Al precodificar el vídeo en el PC del operador con los parámetros correctos (perfil H.264 baseline, nivel 3.0, `-movflags +faststart`), el fichero resultante ya está en el formato exacto que los nodos necesitan. FFmpeg solo tiene que leerlo y reempaquetarlo en el contenedor RTMP, una operación que consume un 10-15% de CPU en lugar del 100%.

El parámetro `-movflags +faststart` merece una mención especial. Mueve los metadatos del vídeo al inicio del fichero, lo que permite que FFmpeg empiece a leerlo y emitirlo inmediatamente sin necesitar procesar todo el fichero primero.

---

## 10. Problemas Encontrados y Soluciones

### Problema 1 — HAProxy no gestionaba RTMP

**Síntoma:** Los nodos HLS no recibían el stream o solo uno de los dos lo recibía.

**Causa:** La configuración inicial de HAProxy solo escuchaba en el puerto 80 (HTTP). El tráfico RTMP del puerto 1935 no era gestionado por ningún componente del balanceador.

**Solución:** FFmpeg envía el stream RTMP directamente a ambos nodos sin pasar por HAProxy. HAProxy gestiona exclusivamente el balanceo HTTP. Esta separación de responsabilidades simplifica la arquitectura y la hace más robusta.

### Problema 2 — Caché excesiva en el portal de Visitantes

**Síntoma:** El vídeo se reproducía con mucho retraso y los clientes recibían fragmentos obsoletos.

**Causa:** La configuración inicial del proxy en Visitantes cacheaba las respuestas durante 1 minuto. Los fragmentos HLS se regeneran cada 3 segundos, por lo que el cliente recibía contenido con hasta 60 segundos de antigüedad.

**Solución:** Eliminación completa de la caché en el proxy de Visitantes y configuración de `proxy_buffering off`. El fichero `.m3u8` nunca debe cachearse en ningún punto de la cadena.

### Problema 3 — Tirones al inicio de la reproducción

**Síntoma:** El vídeo tardaba varios segundos en arrancar y se congelaba en los primeros momentos.

**Causa:** HLS.js con configuración por defecto intenta reproducir con muy poco buffer precargado, lo que hace al reproductor vulnerable a cualquier variación en la velocidad de descarga.

**Solución:** Configuración explícita de HLS.js con `maxBufferLength: 24` y `liveSyncDurationCount: 4`, forzando al reproductor a acumular suficiente contenido antes de empezar la reproducción.

### Problema 4 — Fragmentos de 2 segundos generaban demasiadas peticiones

**Síntoma:** El servidor recibía un volumen muy alto de peticiones HTTP pequeñas, generando overhead de red innecesario.

**Causa:** Con fragmentos de 2 segundos, cada cliente realiza una petición HTTP cada 2 segundos. Con varios usuarios simultáneos, el número de peticiones por segundo se multiplica rápidamente.

**Solución:** Aumento del tamaño de fragmento a 3 segundos. Reduce las peticiones un 33% con un impacto mínimo en la latencia percibida por el usuario.

---

## 11. Limitaciones y Escalabilidad Real

El sistema implementado es funcional y válido para demostración, pero tiene limitaciones inherentes a la escala del laboratorio.

### Capacidad estimada

Con la arquitectura actual, el sistema puede atender aproximadamente **20-40 usuarios simultáneos** antes de que el rendimiento empiece a degradarse. El cuello de botella principal es la red interna de AWS entre la subnet de Visitantes y la subnet de Gestión, que pasa a través del firewall.

### Lo que requeriría un despliegue real

**CDN para la distribución.** En un estadio real con miles de visitantes, ningún servidor puede atender todas las peticiones de fragmentos HLS directamente. Una CDN (Content Delivery Network) cachea los fragmentos en servidores distribuidos geográficamente y los sirve desde el punto más cercano al usuario. El servidor de origen solo recibe la carga de generar el stream, no de distribuirlo.

**Auto Scaling.** La demanda en un estadio es extremadamente variable — máxima durante el partido o concierto, mínima el resto del tiempo. Un Auto Scaling Group crearía y eliminaría nodos HLS automáticamente según la demanda real, optimizando el coste.

**WebRTC para baja latencia.** HLS tiene entre 6 y 30 segundos de latencia por diseño. Para aplicaciones que requieren latencia inferior a 1 segundo (como cámaras de seguridad en tiempo real), se usa WebRTC. El coste en infraestructura es significativamente mayor.

**SRS como servidor de streaming.** nginx-rtmp está abandonado desde 2019. En producción real se utiliza SRS (Simple Realtime Server) o Mediamtx, que soportan cargas mucho mayores con el mismo hardware y tienen soporte activo de la comunidad.

La diferencia entre este laboratorio y lo que Telefónica opera en el Mestalla o el Palau no es el diseño conceptual — es exactamente el mismo — sino la escala de la infraestructura que lo soporta.