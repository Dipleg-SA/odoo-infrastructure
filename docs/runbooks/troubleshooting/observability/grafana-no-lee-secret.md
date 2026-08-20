# Grafana no lee un secret

## Síntoma

Grafana no puede leer su contraseña de admin, o la de SMTP, u otro secret montado.

## Diagnóstico

Su gid primario es `0`, no `472` (el habitual de la imagen de Grafana).

## Fix

El acceso llega por `group_add: ["472","101"]`; si se sacan del compose, Grafana no lee ni su contraseña de admin ni la de SMTP. Revisar que ese `group_add` siga presente en `compose.observability.yaml`.
