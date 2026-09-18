# Verificar un runtime aislado

## Cuándo se usa

Para ensayar staging o producción en el servidor sin reemplazar el stack activo ni reutilizar sus contenedores, volúmenes o timers.

## Objetivo

Copiar el checkout del entorno, asignarle una identidad Compose, puertos y hostname propios, restaurar un snapshot conocido y validar las capas en orden: edge, PostgreSQL, Odoo, backup y monitoring.

La ventana puede excluir Cloudflare cuando el objetivo es validar la aplicación, los datos, el backup y la observabilidad sin abrir una segunda entrada pública.

## Preparación

La copia debe hacerse en una ruta temporal o de verificación con espacio suficiente. El destino no puede existir y debe conservarse el checkout original:

```bash
ORIGEN=/ruta/al/checkout-del-entorno
VERIFICACION=/ruta/al/checkout-del-entorno-verif-<identificador>
cp -r "$ORIGEN" "$VERIFICACION"
cd "$VERIFICACION"
```

Dentro de la copia, ajustá solamente sus archivos privados de entorno:

```dotenv
COMPOSE_PROJECT_NAME=<entorno>-verif-<identificador>
LOCAL_IP=127.0.0.1
HTTP_PORT=<puerto-http-libre>
HTTPS_PORT=<puerto-https-libre>
PUBLIC_HOSTNAME=<hostname-de-verificacion>
ODOO_DISABLE_SMTP=1
```

Los puertos, volúmenes, nombres de contenedor e imágenes deben derivar de la identidad nueva. No se deben reutilizar los nombres del stack activo.

Reutilizá únicamente las copias autorizadas de las credenciales del entorno que se está verificando. No mezcles credenciales de staging y producción, no las imprimas y comprobá sus permisos dentro de la copia:

```bash
sudo ENTORNO=<entorno> make secrets-perms
ENTORNO=<entorno> make secrets-check
docker compose config -q
```

## Flujo por stacks

### 1. Edge

Levantá y verificá Nginx directamente. En una ventana sin Cloudflare no uses `make up`, porque la composición puede incluir el servicio del túnel:

```bash
ENTORNO=<entorno> make nginx-up
ENTORNO=<entorno> make nginx-verify
```

Usá un certificado local de prueba y un hostname de verificación. No emitas certificados públicos desde la copia.

### 2. PostgreSQL y restore

```bash
ENTORNO=<entorno> make postgres-up
ENTORNO=<entorno> make postgres-verify
```

Restaurá después de verificar PostgreSQL y antes de levantar Odoo. Para producción elegí y registrá un ID exacto del snapshot; no uses `latest` en la evidencia de la prueba:

```bash
ENTORNO=<entorno> make restore SNAPSHOT=<snapshot-exacto>
```

El restore debe afectar solamente los volúmenes de la copia.

### 3. Odoo

```bash
ENTORNO=<entorno> make odoo-up
ENTORNO=<entorno> make odoo-report-config
ENTORNO=<entorno> make odoo-verify
```

No continúes si PostgreSQL u Odoo fallan. La configuración de reportes debe apuntar al servicio interno y al hostname de verificación, con `web.base.url.freeze` activo.

### 4. Backup

En una copia aislada, comprobá el repositorio y el snapshot sin escribir uno nuevo:

```bash
ENTORNO=<entorno> make backup-up
ENTORNO=<entorno> make backup-verify
```

No ejecutes `backup-run` ni instales timers: la copia no debe competir con el backup ni con las alertas del entorno activo. El verificador puede informar como excepciones esperadas que el snapshot pertenece al hostname del entorno original y que no existen timers para la copia.

### 5. Monitoring

En producción, levantá el rol de lectura y los servicios de observabilidad:

```bash
ENTORNO=produccion make monitoring-role
ENTORNO=produccion make prometheus-up
ENTORNO=produccion make loki-up
ENTORNO=produccion make grafana-up
ENTORNO=produccion make alloy-up

ENTORNO=produccion make prometheus-verify
ENTORNO=produccion make loki-verify
ENTORNO=produccion make grafana-verify
ENTORNO=produccion make alloy-verify
```

Si Cloudflare fue excluido, Prometheus puede informar caído únicamente el target `cloudflared`. Registrá esa salida como exclusión de alcance; no levantes el túnel solo para convertir la verificación en verde.

## Criterios de cierre

La ventana queda validada cuando:

- el stack activo conserva sus contenedores y estado;
- la copia usa identidad, puertos y volúmenes propios;
- el snapshot exacto se restaura sin escribir en el repositorio;
- PostgreSQL, Odoo, Nginx/HTTPS y los stacks aplicables pasan sus verificaciones;
- el SMTP queda deshabilitado;
- las exclusiones —Cloudflare, timers y cualquier target dependiente— quedan registradas;
- una petición HTTPS con el hostname de verificación responde `200`.

La verificación aislada no reemplaza la validación del entorno productivo activo de DNS, SMTP, webhooks, certificados y timers.
