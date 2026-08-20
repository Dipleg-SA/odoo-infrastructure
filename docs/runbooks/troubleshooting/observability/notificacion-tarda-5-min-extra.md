# Un segundo servicio caído tarda ~5 min extra en avisar

## Síntoma

Cuando un segundo servicio se cae poco después del primero, la notificación del segundo llega con un retraso de varios minutos de más.

## Diagnóstico

Agrupación de notificaciones demasiado amplia. Ya se agrupa por `alertname, job, name` para tener un techo de 5 minutos.

## Fix

Ninguno — es el comportamiento esperado con esa agrupación. Si se cambia a agrupar solo por `alertname`, se pierde ese techo y el retraso puede crecer más — no achicar el agrupamiento sin entender esta consecuencia.
