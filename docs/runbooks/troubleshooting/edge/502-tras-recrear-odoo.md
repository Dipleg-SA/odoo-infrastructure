# 502 justo después de recrear Odoo, con nginx sano

## Síntoma

Odoo se recreó (nuevo contenedor, nueva IP) y nginx empieza a devolver 502, aunque el servicio esté sano.

## Diagnóstico

Es el caché de resolución de nginx: resuelve los upstream al arrancar y se queda con la IP vieja. El repositorio lo previene con `resolver 127.0.0.11 valid=10s` y `proxy_pass` a través de una variable, que es lo que obliga a reconsultar. Si alguien reescribió la location con el nombre fijo (`proxy_pass http://odoo:8069;`), el síntoma vuelve — lo chequea `make nginx-verify`.

La contracara de ese diseño es una línea de log: mientras Odoo no está —el arranque de un stack nuevo, los segundos de un `odoo-restart`—, **cada** request deja un `[error] ... odoo could not be resolved (2: Server failure)`. Es correcto y no hay nada que arreglar; en un hostname público los escáneres se encargan de que aparezca siempre. Por eso `verify` no la cuenta como fallo: lo que la resolución funcione lo prueba en vivo el chequeo «la cadena nginx → Odoo responde», que sale por el proxy y vuelve a la aplicación.

## Fix

Mitigación inmediata:

```bash
docker compose exec nginx nginx -s reload
```

Si vuelve a pasar después de cada recreación de Odoo, revisar que `stacks/nginx/` no haya perdido el patrón de `resolver` + variable en el `proxy_pass`.
