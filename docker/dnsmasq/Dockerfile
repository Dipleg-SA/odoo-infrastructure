# --- Base ---
# Pineada como todo lo demás. A diferencia de las imágenes upstream, nada avisa
# cuando la rama base deja de recibir parches: revisá su ventana de soporte al
# actualizar el resto del stack. Releases y EOL: https://alpinelinux.org/releases/

FROM alpine:3.20

# --- dnsmasq ---
# Corre como root: el 53 es puerto privilegiado y el contenedor usa el stack de
# red del host. dnsmasq baja de privilegios por su cuenta después de bindear.

RUN apk add --no-cache dnsmasq
ENTRYPOINT ["dnsmasq"]
