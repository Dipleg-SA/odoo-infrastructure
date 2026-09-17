# Gestionar dependencias Python de addons

## Cuándo se usa

Cuando un repositorio agrega o cambia un `requirements.txt`, un manifiesto modifica `external_dependencies.python` o el deployment necesita una excepción local.

## Objetivo

Construir la imagen desde los requisitos declarados por los mismos commits de addons que entran en la fotografía. Los manifiestos comprueban cobertura; `runtime/addons/requirements.override.txt` agrega solo excepciones del deployment y el lock generado no se edita.

## Flujo rápido

1. Declarar la instalación en un `requirements.txt` del repositorio responsable.
2. Declarar el módulo importable en `external_dependencies.python`.
3. Ejecutar `ENTORNO=<entorno> make addons-deps` para validar y compilar el lock operativo.
4. Ejecutar `ENTORNO=<entorno> make build`; el build repite la compilación contra su fotografía.

## A mano

Los archivos pueden vivir en la raíz del repositorio o dentro de un módulo. Se conservan rangos, pines, marcadores y referencias Git. Las ramas y tags Git se resuelven a commits completos durante `compile`; una referencia inexistente detiene el build.

El override local se usa cuando un addon declara un import que su repositorio no instala o cuando el deployment necesita un pin excepcional. Una entrada con el mismo nombre reemplaza las declaraciones de los repositorios; las demás se agregan. El archivo histórico `runtime/addons/requirements.txt` ya no participa del build.

Las directivas relativas `-r`, `-c` y los requisitos editables se rechazan porque no pueden aplanarse en un lock autocontenido sin cambiar su semántica. Declarar el requisito directamente en el mismo archivo.

Las referencias Git fijadas se empaquetan dentro de la fotografía. Docker compila todos los wheels, incluidos los que necesitan herramientas nativas, en una etapa temporal; la imagen final instala solo los wheels y no conserva compiladores.

## Comandos

```bash
cp runtime/addons/requirements.override.txt.example runtime/addons/requirements.override.txt
ENTORNO=desarrollo scripts/pydeps.sh check
ENTORNO=desarrollo scripts/pydeps.sh compile
ENTORNO=desarrollo make build
```

## Verificación

`check` debe informar que todos los imports declarados están cubiertos. `compile` debe generar `runtime/addons/requirements.lock.txt`; las referencias `git+` de ese archivo deben terminar en un SHA completo y no en una rama o tag móvil. Cada build conserva además su propio lock bajo `runtime/addons/builds/<entorno>/<identificador>/requirements.lock.txt`.
