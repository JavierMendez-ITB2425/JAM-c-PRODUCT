# Script para Eliminar Agentes de Wazuh Manager en Docker

```bash
#!/bin/bash

# Nombre del contenedor del Manager
CONTENEDOR="single-node-wazuh.manager-1"

echo "--- LISTA DE AGENTES ACTUALES ---"
# Ejecutamos el listado dentro del contenedor
sudo docker exec -it $CONTENEDOR /var/ossec/bin/manage_agents -l

echo ""
echo "------------------------------------------------"
read -p "Introduce el ID del agente que quieres BORRAR: " AGENT_ID

if [ -z "$AGENT_ID" ]; then
    echo "❌ Error: No has introducido ningún ID."
    exit 1
fi

echo "--- ELIMINANDO AGENTE ID: $AGENT_ID ---"
# Ejecutamos la eliminación pasándole el ID
sudo docker exec -it $CONTENEDOR /var/ossec/bin/manage_agents -r $AGENT_ID

echo ""
echo "✅ Proceso finalizado. El agente $AGENT_ID ha sido eliminado del Manager."
```

## Uso
```bash
chmod +x borrar_agente.sh
```

```bash
./borrar_agente.sh
```

## Qué hace este script

1. Muestra la lista de agentes registrados en el Wazuh Manager.
2. Solicita el ID del agente que deseas eliminar.
3. Ejecuta la eliminación directamente dentro del contenedor Docker.
4. Confirma cuando el proceso ha finalizado.
