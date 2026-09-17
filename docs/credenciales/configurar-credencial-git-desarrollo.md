# Configurar credencial Git de desarrollo

## Cuándo se usa

Antes del primer `ENTORNO=desarrollo make repo-sync` en una máquina de desarrollo. Ese comando puede crear la rama declarada `feat/*` desde `19.0` en cada dominio del catálogo.

## Objetivo

Una credencial de desarrollo con lectura y escritura limitada a las ramas `feat/*` de los repositorios de addons. No se instala en staging ni producción.

## Flujo rápido

1. Crear una credencial separada con lectura de contenidos y creación/actualización de `feat/*`.
2. Configurarla en el credential store de la máquina de desarrollo.
3. Proteger `19.0` y `19.0-stag` en el proveedor para que esa credencial no pueda modificarlas.
4. Ejecutar `ENTORNO=desarrollo make repo-sync` y confirmar las ramas creadas.

## A mano

La restricción de ramas se aplica en el proveedor Git, no en una condición local. La credencial puede crear la feature declarada por desarrollo, pero no puede escribir `19.0`, `19.0-stag`, tags ni repositorios fuera del catálogo.

## Verificación

`ENTORNO=desarrollo make repo-sync` debe publicar candidatos desde la `feat/*` declarada. Staging y producción siguen fallando si falta su rama fija y no deben crear referencias remotas.
