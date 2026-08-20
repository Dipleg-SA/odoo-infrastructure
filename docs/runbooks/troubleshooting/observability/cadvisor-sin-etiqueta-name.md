# cadvisor emite series sin etiqueta name

## Síntoma

Las métricas de contenedores llegan sin la etiqueta `name`, así que no se puede saber a qué contenedor pertenece cada serie.

## Diagnóstico

Alloy no alcanza el socket de containerd.

## Fix

Verificar el montaje `/run/containerd/containerd.sock:ro`; sin él, Alloy no enumera contenedores y las métricas por contenedor quedan anónimas.
