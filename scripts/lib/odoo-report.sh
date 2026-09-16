#!/usr/bin/env bash
# Resolución compartida de las URLs que Odoo usa para reportes y enlaces.
# Este archivo no tiene efectos secundarios: solo calcula variables y valida
# que la configuración declarada sea utilizable.

odoo_report_resolve_urls() {
  ODOO_REPORT_URL_ERROR=""
  REPORT_URL="${REPORT_URL:-http://odoo:8069}"
  PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}"

  if [ -z "$PUBLIC_BASE_URL" ]; then
    case "${ENTORNO:-}" in
      desarrollo)
        if [ -z "${HTTP_PORT:-}" ]; then
          ODOO_REPORT_URL_ERROR="falta HTTP_PORT en runtime/desarrollo/compose.env"
          return 1
        fi
        PUBLIC_BASE_URL="http://127.0.0.1:${HTTP_PORT}"
        ;;
      staging|produccion)
        if [ -z "${PUBLIC_HOSTNAME:-}" ]; then
          ODOO_REPORT_URL_ERROR="falta PUBLIC_HOSTNAME en runtime/$ENTORNO/compose.env"
          return 1
        fi
        PUBLIC_BASE_URL="https://${PUBLIC_HOSTNAME}"
        ;;
      *)
        ODOO_REPORT_URL_ERROR="ENTORNO no es válido; usar desarrollo, staging o produccion"
        return 1
        ;;
    esac
  fi

  case "$REPORT_URL" in
    http://*|https://*) ;;
    *)
      ODOO_REPORT_URL_ERROR="REPORT_URL debe comenzar con http:// o https://: $REPORT_URL"
      return 1
      ;;
  esac

  case "$PUBLIC_BASE_URL" in
    http://*|https://*) ;;
    *)
      ODOO_REPORT_URL_ERROR="PUBLIC_BASE_URL debe comenzar con http:// o https://: $PUBLIC_BASE_URL"
      return 1
      ;;
  esac
}
