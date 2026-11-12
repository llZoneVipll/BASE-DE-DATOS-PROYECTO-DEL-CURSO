-- Ejecuta todos los scripts en orden. Correr desde la carpeta scripts/:
-- CMD / Linux : mysql -u root -p --default-character-set=utf8mb4 --local-infile=1 < ejecutar_todo.sql
-- PowerShell  : mysql -u root -p --default-character-set=utf8mb4 --local-infile=1 -e "source ejecutar_todo.sql"

SOURCE 01_esquema.sql;
SOURCE 02_seguridad.sql;
SOURCE 03_catalogos.sql;
SOURCE 04_objetos_campo_fitosanitario.sql;
SOURCE 05_objetos_acopio_embarque.sql;
SOURCE 06_carga_campo.sql;
SOURCE 07_carga_acopio_embarque.sql;
SOURCE 08_pruebas.sql;
