# Bigcapital self-hosted para Coolify

Deploy adaptado del `docker-compose.prod.yml` oficial de [bigcapitalhq/bigcapital](https://github.com/bigcapitalhq/bigcapital) (AGPL-3.0).

## Diferencias vs. el compose oficial

| Upstream | Aquí | Por qué |
|---|---|---|
| `proxy` publica `80:80` / `443:443` | `proxy` solo `expose: 80` | Coolify/Traefik maneja el dominio y TLS. Publicar 80/443 choca con Traefik. |
| `garage` (S3 self-hosted) | **omitido** → S3 externo (Cloudflare R2) | Ya usas R2 en Chatmu; evita clonar el repo y montar configs. |
| `clickhouse` | **omitido** (`CLICKHOUSE_ENABLED=false`) | Analytics opcional. |
| `auto-update` (watchtower) | **omitido** | Coolify gestiona las actualizaciones. Además watchtower monta el docker.sock (riesgo). |
| `mysql` build custom | `mariadb:10.2` + GRANT inline (`configs`) | El build solo agregaba `bind-address` y el GRANT; se replica con un `config` inline. |
| `redis` build custom | `redis:6.2.21` + `--appendonly yes` | Equivalente. |
| `database_migration` build | `bigcapitalhq/server:latest` + comando | Evita clonar el repo; usa la misma imagen del server. |

---

## Instalación en Coolify

### 1. Crear los secretos

```sh
openssl rand -base64 48   # APP_JWT_SECRET
openssl rand -base64 32   # DB_PASSWORD
openssl rand -hex 24      # DB_ROOT_PASSWORD
```

### 2. Configurar `.env`

```sh
cp .env.example .env
# edita .env y llena al menos: BASE_URL, APP_JWT_SECRET, DB_PASSWORD, DB_ROOT_PASSWORD, MAIL_*
```

> ℹ️ **Autocontenido**: la config de Envoy (`/etc/envoy/envoy.yaml`) y el GRANT de MySQL
> (`/docker-entrypoint-initdb.d/10-grant.sql`) van **inline** en el compose con `configs:`.
> No dependen de archivos del repo. Si cambias `DB_USER`, actualiza el bloque `mysql_grant`
> dentro de `docker-compose.coolify.yml` (debe coincidir con `DB_USER`).

### 3. Crear el recurso en Coolify

1. Coolify → **+ New Resource → Docker Compose** (o "Public Repository").
2. Apunta al repo/carpeta que contiene `docker-compose.coolify.yml`.
3. En **Environment Variables**, pega el contenido de tu `.env`.
4. En **Domains**, asigna tu dominio (ej. `https://finance.chatmu.io`) al servicio **`proxy`**, puerto **`80`**.
5. **Deploy**.

El servicio `migration` corre una vez y **termina con exit 0** (es lo esperado). Si Coolify lo marca como detenido, ignóralo.

### 4. Primer uso

- Abre el dominio → crea la **primera cuenta** (no hay usuario por defecto).
- Confirma que las migraciones corrieron:
  ```sh
  docker logs bigcapital-database-migration
  ```
  Debes ver `system:migrate:latest` y `tenants:migrate:latest` sin errores.

---

## Configurar S3 (Cloudflare R2)

Como se omitió `garage`, los adjuntos (logos, PDFs) van a R2. Crea un bucket y llena:

```
S3_REGION=auto
S3_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_BUCKET=chatmu-finance
S3_FORCE_PATH_STYLE=true
```

Si el bucket da error de "NoSuchBucket", créalo antes en el dashboard de R2.

---

## Correo (Resend)

El mail sirve para: **invitar usuarios/socios**, mandar facturas/estimados/recibos a clientes,
recuperar contraseña y confirmar registro. El app arranca sin mail, pero **no podrás invitar socios**.

Resend funciona por SMTP. Llena así:

```env
MAIL_HOST=smtp.resend.com
MAIL_PORT=465
MAIL_SECURE=true
MAIL_USERNAME=resend
MAIL_PASSWORD=re_...API_KEY...
MAIL_FROM_NAME=Chatmu Billing
MAIL_FROM_ADDRESS=billing@updates.aaatmi.com
```

Notas:
- `updates.aaatmi.com` **ya está verificado en Resend** → funciona al instante.
- Puerto `465` = SSL implícito (`MAIL_SECURE=true`). Si usas `587`, pon `MAIL_SECURE=false`.
- Es **solo envío**. No se necesita recibir ni configurar webhooks de Resend para Bigcapital.

---

## Stripe — ¿para qué sirve? (opcional)

`STRIPE_PAYMENT_*` NO sirve para importar los ingresos que ya cobras en Chatmu.
Sirve para **cobrar las facturas que emitas desde Bigcapital**: genera links de pago
(Stripe Checkout) y registra el pago automáticamente cuando el cliente paga.

- **Úsalo** si vas a facturar clientes desde Bigcapital y quieres "pagar ahora" con tarjeta.
- **No lo necesitas** si sigues cobrando con tu Stripe actual de Chatmu → esos ingresos
  entran por **import CSV** (Balance transactions / Payouts).
- Es Stripe **Connect** (OAuth): conectas tu cuenta desde Bigcapital.

**Recomendación:** déjalo vacío al inicio. Agrégalo solo si empiezas a facturar desde aquí.

Webhook a configurar en Stripe: `https://<TU_DOMINIO>/api/webhooks/stripe`
Eventos: `checkout.session.completed`, `account.updated`.

---

## Actualizar

```sh
docker compose -f docker-compose.coolify.yml pull
docker compose -f docker-compose.coolify.yml up -d
# y re-correr migraciones:
docker compose -f docker-compose.coolify.yml run --rm migration
```

---

## Backup

Lo importante son los volúmenes **`mysql_data`** y **`redis_data`**.

```sh
docker exec bigcapital-mysql \
  mysqldump -u root -p"$DB_ROOT_PASSWORD" --all-databases > backup-$(date +%F).sql
```

Programa esto en Coolify (scheduled task) o en cron del host. **Sin backup no hay contabilidad.**
