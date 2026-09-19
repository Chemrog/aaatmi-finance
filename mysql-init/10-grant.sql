-- Init de MariaDB (solo corre la PRIMERA vez, con el volumen vacío).
--
-- El usuario 'bigcapital' (o el DB_USER que configures) YA lo crea la imagen
-- oficial de MariaDB con MYSQL_USER / MYSQL_PASSWORD del .env.
-- Aquí solo le damos privilegios globales para que pueda CREAR las bases de
-- datos por tenant en runtime (la imagen oficial solo da permisos sobre una DB).
--
-- NOTA: el nombre de usuario debe coincidir con DB_USER del .env.
-- Por seguridad, NO poner contraseñas en este archivo.

GRANT ALL PRIVILEGES ON *.* TO 'bigcapital'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
