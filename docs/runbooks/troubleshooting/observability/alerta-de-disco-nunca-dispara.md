# La alerta de disco nunca dispara

## Síntoma

El disco se llena y la alerta de espacio no salta.

## Diagnóstico

Filtro por `mountpoint` que no existe en ese host.

## Fix

La regla filtra por `fstype` justamente para no depender del nombre del punto de montaje. Si la alerta sigue sin disparar, revisar que el `fstype` del disco real coincida con el que la regla espera — no reintroducir un filtro por `mountpoint`.
