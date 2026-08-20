# 502 justo después de recrear Odoo, con nginx sano

## Síntoma

Odoo se recreó (nuevo contenedor, nueva IP) y nginx empieza a devolver 502, aunque el servicio esté sano.

## Diagnóstico

Es el caché de resolución de nginx: resuelve los upstream al arrancar y se queda con la IP vieja. El repositorio lo previene con `resolver 127.0.0.11 valid=10s` y `proxy_pass` a través de una variable, que es lo que obliga a reconsultar. Si alguien reescribió la location con el nombre fijo (`proxy_pass http://odoo:8069;`), el síntoma vuelve — lo chequea `make edge-verify`.

## Fix

Mitigación inmediata:

```bash
docker compose exec nginx nginx -s reload
```

Si vuelve a pasar después de cada recreación de Odoo, revisar que `config/nginx/` no haya perdido el patrón de `resolver` + variable en el `proxy_pass`.
