#!/bin/bash
# 0. Redirigir toda la salida a un log para poder depurar (en /var/log/user-data.log)
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
export DEBIAN_FRONTEND=noninteractive

echo "=== INICIANDO DESPLIEGUE DE MONGODB PARA BODEGA PEIRANO ==="

# 1. Esperar que se libere el bloqueo de paquetes de AWS
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 10; done

# 2. Instalar dependencias y llave de MongoDB 7.0
apt-get update
apt-get install -y gnupg curl lsb-release

curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg \
   --dearmor --yes

# Forzar la versión a "jammy" (Ubuntu 22.04) para compatibilidad con MongoDB 7.0
UBUNTU_CODENAME="jammy"
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $UBUNTU_CODENAME/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list

apt-get update
apt-get install -y mongodb-org

# 3. Iniciar el servicio y esperar a que el puerto 27017 esté listo
systemctl daemon-reload
systemctl enable mongod
systemctl start mongod
sleep 15

# 4. Crear usuario administrador
mongosh <<EOF
use admin
db.createUser({
  user: "admin",
  pwd: "Mongo12345!",
  roles: [ { role: "root", db: "admin" } ]
})
EOF

# 5. Configurar bindIp a 0.0.0.0 y activar autenticación
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

cat >> /etc/mongod.conf <<EOF
security:
  authorization: enabled
EOF

# 6. Reiniciar MongoDB para aplicar la seguridad
systemctl restart mongod
sleep 15

# 7. Crear el script JS de inicialización de datos de la bodega
cat << 'EOF_JS' > /tmp/init-bodega.js
db = db.getSiblingDB('BodegaPeiranoDB');

db.ubigeo.deleteMany({});
db.categoria.deleteMany({});
db.producto.deleteMany({});
db.cliente.deleteMany({});
db.almacen.deleteMany({});
db.metodo_pago.deleteMany({});

db.ubigeo.insertMany([
    { _id: "150101", distrito: "Lima", provincia: "Lima", departamento: "Lima" },
    { _id: "150102", distrito: "Asia", provincia: "Cañete", departamento: "Lima" },
    { _id: "150103", distrito: "Chilca", provincia: "Cañete", departamento: "Lima" },
    { _id: "150104", distrito: "Mala", provincia: "Cañete", departamento: "Lima" },
    { _id: "150105", distrito: "San Vicente de Cañete", provincia: "Cañete", departamento: "Lima" },
    { _id: "150106", distrito: "Imperial", provincia: "Cañete", departamento: "Lima" },
    { _id: "150108", distrito: "Lunahuana", provincia: "Cañete", departamento: "Lima" },
    { _id: "150201", distrito: "Arequipa", provincia: "Arequipa", departamento: "Arequipa" },
    { _id: "150202", distrito: "Cayma", provincia: "Arequipa", departamento: "Arequipa" },
    { _id: "150203", distrito: "Yanahuara", provincia: "Arequipa", departamento: "Arequipa" },
    { _id: "150301", distrito: "Cusco", provincia: "Cusco", departamento: "Cusco" },
    { _id: "150302", distrito: "San Jeronimo", provincia: "Cusco", departamento: "Cusco" },
    { _id: "150401", distrito: "Trujillo", provincia: "Trujillo", departamento: "La Libertad" },
    { _id: "150402", distrito: "Victor Larco", provincia: "Trujillo", departamento: "La Libertad" },
    { _id: "150501", distrito: "Piura", provincia: "Piura", departamento: "Piura" },
    { _id: "150502", distrito: "Castilla", provincia: "Piura", departamento: "Piura" }
]);

const ahora = new Date();

db.categoria.insertMany([
    { _id: 1, nombre: "Pisco",    descripcion: "Destilados de uva",                 codigo_categoria: "PIS", estado: true, fecha_creacion: ahora },
    { _id: 2, nombre: "Vino",     descripcion: "Vinos tintos, blancos y semisecos", codigo_categoria: "VIN", estado: true, fecha_creacion: ahora },
    { _id: 3, nombre: "Sangría",  descripcion: "Bebidas a base de vino y frutas",   codigo_categoria: "SAN", estado: true, fecha_creacion: ahora },
    { _id: 4, nombre: "Jarabes",  descripcion: "Jarabes para coctelería",           codigo_categoria: "JAR", estado: true, fecha_creacion: ahora }
]);

db.producto.insertMany([
    { _id: 1, nombre: "PISCO PEIRANO PURO QUEBRANTA botella 750 ml.", descripcion: "Pisco puro quebranta artesanal", codigo_barras_sku: "7750123456789", unidad_medida: "750ml", precio_unitario: 30.00, id_categoria: 1, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 2, nombre: "PISCO PEIRANO PURO ITALIA botella 750 ml.",    descripcion: "Pisco puro italia premium",        codigo_barras_sku: "7750987654321", unidad_medida: "750ml", precio_unitario: 30.00, id_categoria: 1, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 3, nombre: "PISCO PEIRANO ACHOLADO botella 750 ml.",       descripcion: "Pisco acholado especial",          codigo_barras_sku: "7750223344556", unidad_medida: "750ml", precio_unitario: 30.00, id_categoria: 1, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 4, nombre: "PISCO PEIRANO PURO QUEBRANTA galon 4 Lt.",     descripcion: "Pisco quebranta galón",            codigo_barras_sku: "SKU-PIS-QUE-GAL", unidad_medida: "Galon 4L", precio_unitario: 120.00, id_categoria: 1, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 5, nombre: "PISCO PEIRANO PURO ITALIA galon 4 Lt.",        descripcion: "Pisco italia galón",               codigo_barras_sku: "SKU-PIS-ITA-GAL", unidad_medida: "Galon 4L", precio_unitario: 120.00, id_categoria: 1, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 6, nombre: "PISCO PEIRANO ACHOLADO galon 4 Lt.",           descripcion: "Pisco acholado galón",             codigo_barras_sku: "SKU-PIS-ACH-GAL", unidad_medida: "Galon 4L", precio_unitario: 100.00, id_categoria: 1, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 7, nombre: "Vino EUMA Tinto (Seco) botella 750 ml.",       descripcion: "Vino tinto seco",                  codigo_barras_sku: "SKU-VIN-EUM-TIN", unidad_medida: "750ml", precio_unitario: 22.00, id_categoria: 2, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 8, nombre: "Vino EUMA Tinto (Semi Seco) botella 750 ml.",  descripcion: "Vino tinto semiseco",              codigo_barras_sku: "SKU-VIN-EUM-SEM", unidad_medida: "750ml", precio_unitario: 22.00, id_categoria: 2, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 9, nombre: "Vino EUMA Blanco (Dulce) botella 750 ml.",     descripcion: "Vino blanco dulce",                codigo_barras_sku: "SKU-VIN-EUM-BLA", unidad_medida: "750ml", precio_unitario: 22.00, id_categoria: 2, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 10, nombre: "SANGRIA TINTA SANGRIA 1L.",   descripcion: "Sangría tinta lista para servir",  codigo_barras_sku: "SKU-SAN-TIN-1L", unidad_medida: "1L", precio_unitario: 12.00, id_categoria: 3, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 11, nombre: "SANGRIA BLANCA BLANGRIA 1L.", descripcion: "Sangría blanca lista para servir", codigo_barras_sku: "SKU-SAN-BLA-1L", unidad_medida: "1L", precio_unitario: 12.00, id_categoria: 3, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 12, nombre: "Jarabe de Goma JAPI botella 750 ml.",       descripcion: "Jarabe de goma para coctelería",      codigo_barras_sku: "SKU-JAR-GOM-750", unidad_medida: "750ml", precio_unitario: 7.00, id_categoria: 4, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null },
    { _id: 13, nombre: "Jarabe de Granadina JAPI botella 750 ml.", descripcion: "Jarabe de granadina para coctelería", codigo_barras_sku: "SKU-JAR-GRA-750", unidad_medida: "750ml", precio_unitario: 8.00, id_categoria: 4, estado: true, fecha_creacion: ahora, fecha_actualizacion: null, fecha_eliminacion: null, fecha_restauracion: null }
]);

db.cliente.insertMany([
    { _id: 1, tipo_documento: 'DNI', numero_documento: '72145678',  nombre: 'Sebastian',          apellido: 'Alvarez', correo: 'sebastian@mail.com',   telefono: '987654321', fecha_nacimiento: '1990-05-15', ubigeo_id: '150101', estado: true, fecha_creacion: ahora },
    { _id: 2, tipo_documento: 'DNI', numero_documento: '45678912',  nombre: 'Angel',              apellido: 'Perez',   correo: 'angel.p@mail.com',     telefono: '999888777', fecha_nacimiento: '1985-08-20', ubigeo_id: '150102', estado: true, fecha_creacion: ahora },
    { _id: 3, tipo_documento: 'CE',  numero_documento: '00123456',  nombre: 'Valeriano',          apellido: 'Gomez',   correo: 'valeriano@mail.com',   telefono: '912345678', fecha_nacimiento: '1982-12-10', ubigeo_id: '150103', estado: true, fecha_creacion: ahora },
    { _id: 4, tipo_documento: 'DNI', numero_documento: '12345678',  nombre: 'Maria',              apellido: 'Sosa',    correo: 'maria.sosa@mail.com',  telefono: '955444333', fecha_nacimiento: '1995-03-25', ubigeo_id: '150101', estado: true, fecha_creacion: ahora },
    { _id: 5, tipo_documento: 'RUC', numero_documento: '20123456789', nombre: 'Distribuidora Asia', apellido: 'SAC',   correo: 'ventas@asiacorp.pe',   telefono: '944333222', fecha_nacimiento: '1990-01-01', ubigeo_id: '150102', estado: true, fecha_creacion: ahora }
]);

db.almacen.insertMany([
    { _id: 1, nombre: "Bodega Principal - Asia", ubicacion: "Av. Principal 123, Asia",  codigo_almacen: "BOD-001", ubigeo_id: "150102", estado: "Activo", fecha_creacion: ahora },
    { _id: 2, nombre: "Bodega Costa Azul",       ubicacion: "Carretera Panamericana Sur", codigo_almacen: "BOD-002", ubigeo_id: "150103", estado: "Activo", fecha_creacion: ahora },
    { _id: 3, nombre: "Bodega Norteña",          ubicacion: "Industrial Mz A Lt 5",       codigo_almacen: "BOD-003", ubigeo_id: "150401", estado: "Activo", fecha_creacion: ahora },
    { _id: 4, nombre: "Almacén Central Lima",    ubicacion: "San Isidro 321",             codigo_almacen: "BOD-007", ubigeo_id: "150101", estado: "Activo", fecha_creacion: ahora }
]);

db.metodo_pago.insertMany([
    { _id: 1, nombre: 'Efectivo',           es_electronico: false, estado: true },
    { _id: 2, nombre: 'Yape',               es_electronico: true,  estado: true },
    { _id: 3, nombre: 'Plin',               es_electronico: true,  estado: true },
    { _id: 4, nombre: 'Tarjeta Visa',       es_electronico: true,  estado: true },
    { _id: 5, nombre: 'Transferencia BCP',  es_electronico: true,  estado: true }
]);

print("✅ MongoDB: Datos maestros insertados correctamente.");
EOF_JS

# 8. Ejecutar el script JS usando el usuario administrador
mongosh -u "admin" -p "Mongo12345!" --authenticationDatabase "admin" /tmp/init-bodega.js

# 9. Limpiar el script temporal por seguridad
rm /tmp/init-bodega.js
echo "=== DESPLIEGUE FINALIZADO ==="