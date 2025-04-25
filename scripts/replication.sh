#!/bin/bash

# Настройки
MASTER_CONTAINER=postgres-master
SLAVE_CONTAINER=postgres-slave
DB_USER=postgres
DB_NAME=store_db
REPLICA_USER=replica_user
REPLICA_PASSWORD="mysecretpassword"  
MASTER_HOST="postgres-master"
MASTER_PORT=5434
REPLICA_HOST=localhost
REPLICA_PORT=5435
LOG_FILE=~/postgres-store/backups/replication.log
ERROR_LOG=~/postgres-store/backups/backup_error.log
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)
SLAVE_DATA_DIR=~/postgres-store/slave-data
MASTER_CONF_FILE=~/postgres-store/config/master/postgresql.conf
MASTER_PG_HBA_FILE=~/postgres-store/config/master/pg_hba.conf
SLAVE_CONF_FILE=~/postgres-store/config/slave/postgresql.conf
POSTGRES_VERSION=17  # Версия PostgreSQL (совпадает с backup.sh)

# Создаем папку для логов, если она не существует
mkdir -p ~/postgres-store/backups

# 1. Проверяем, что контейнеры запущены
echo "[$TIMESTAMP] Проверка состояния контейнеров..." >> "$LOG_FILE"
docker ps | grep "$MASTER_CONTAINER" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Мастер-контейнер $MASTER_CONTAINER не запущен!" >> "$ERROR_LOG"
    exit 1
fi

docker ps | grep "$SLAVE_CONTAINER" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Слейв-контейнер $SLAVE_CONTAINER не запущен!" >> "$ERROR_LOG"
    exit 1
fi

# 2. Проверяем и создаем пользователя репликации на мастере
echo "[$TIMESTAMP] Проверка пользователя репликации $REPLICA_USER на мастере..." >> "$LOG_FILE"
docker exec -t "$MASTER_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT 1 FROM pg_roles WHERE rolname='$REPLICA_USER';" | grep -q "1 row" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Создаем пользователя $REPLICA_USER для репликации..." >> "$LOG_FILE"
    docker exec -t "$MASTER_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
        "CREATE ROLE $REPLICA_USER WITH REPLICATION LOGIN PASSWORD '$REPLICA_PASSWORD';" 2>> "$ERROR_LOG"
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Пользователь $REPLICA_USER успешно создан" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Ошибка при создании пользователя $REPLICA_USER" >> "$ERROR_LOG"
        exit 1
    fi
else
    echo "[$TIMESTAMP] Пользователь $REPLICA_USER уже существует" >> "$LOG_FILE"
fi

# 3. Настраиваем postgresql.conf на мастере
echo "[$TIMESTAMP] Настройка postgresql.conf на мастере..." >> "$LOG_FILE"
if ! grep -q "wal_level = replica" "$MASTER_CONF_FILE"; then
    cat <<EOT >> "$MASTER_CONF_FILE"
wal_level = replica
max_wal_senders = 3
EOT
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Настройки репликации добавлены в $MASTER_CONF_FILE" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Ошибка при добавлении настроек в $MASTER_CONF_FILE" >> "$ERROR_LOG"
        exit 1
    fi
else
    echo "[$TIMESTAMP] Настройки репликации уже присутствуют в $MASTER_CONF_FILE" >> "$LOG_FILE"
fi

# Копируем postgresql.conf в контейнер мастера
docker cp "$MASTER_CONF_FILE" "$MASTER_CONTAINER":/var/lib/postgresql/data/postgresql.conf 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Файл postgresql.conf скопирован в контейнер $MASTER_CONTAINER" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при копировании postgresql.conf в $MASTER_CONTAINER" >> "$ERROR_LOG"
    exit 1
fi

# 4. Настраиваем pg_hba.conf на мастере
echo "[$TIMESTAMP] Настройка pg_hba.conf на мастере..." >> "$LOG_FILE"
if ! grep -q "host replication $REPLICA_USER" "$MASTER_PG_HBA_FILE"; then
    echo "host replication $REPLICA_USER 0.0.0.0/0 md5" >> "$MASTER_PG_HBA_FILE"
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Настройка репликации добавлена в $MASTER_PG_HBA_FILE" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Ошибка при добавлении настроек в $MASTER_PG_HBA_FILE" >> "$ERROR_LOG"
        exit 1
    fi
else
    echo "[$TIMESTAMP] Настройка репликации уже присутствует в $MASTER_PG_HBA_FILE" >> "$LOG_FILE"
fi

# Копируем pg_hba.conf в контейнер мастера
docker cp "$MASTER_PG_HBA_FILE" "$MASTER_CONTAINER":/var/lib/postgresql/data/pg_hba.conf 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Файл pg_hba.conf скопирован в контейнер $MASTER_CONTAINER" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при копировании pg_hba.conf в $MASTER_CONTAINER" >> "$ERROR_LOG"
    exit 1
fi

# Перезапускаем мастер для применения настроек
echo "[$TIMESTAMP] Перезапуск контейнера $MASTER_CONTAINER..." >> "$LOG_FILE"
docker restart "$MASTER_CONTAINER" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Контейнер $MASTER_CONTAINER успешно перезапущен" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при перезапуске $MASTER_CONTAINER" >> "$ERROR_LOG"
    exit 1
fi

# 5. Создаем файл standby.signal на слейве, если его нет
echo "[$TIMESTAMP] Проверка наличия файла standby.signal..." >> "$LOG_FILE"
if [ ! -f "$SLAVE_DATA_DIR/standby.signal" ]; then
    echo "[$TIMESTAMP] Создаем файл standby.signal в $SLAVE_DATA_DIR..." >> "$LOG_FILE"
    touch "$SLAVE_DATA_DIR/standby.signal" 2>> "$ERROR_LOG"
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Файл standby.signal успешно создан" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Ошибка при создании файла standby.signal" >> "$ERROR_LOG"
        exit 1
    fi
else
    echo "[$TIMESTAMP] Файл standby.signal уже существует в $SLAVE_DATA_DIR" >> "$LOG_FILE"
fi

# 6. Настраиваем primary_conninfo в postgresql.conf на слейве
echo "[$TIMESTAMP] Настройка primary_conninfo в $SLAVE_CONF_FILE..." >> "$LOG_FILE"
if ! grep -q "primary_conninfo" "$SLAVE_CONF_FILE"; then
    cat <<EOT >> "$SLAVE_CONF_FILE"
primary_conninfo = 'host=$MASTER_HOST port=$MASTER_PORT user=$REPLICA_USER password=$REPLICA_PASSWORD'
hot_standby = on
EOT
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] primary_conninfo успешно добавлен в $SLAVE_CONF_FILE" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Ошибка при добавлении primary_conninfo в $SLAVE_CONF_FILE" >> "$ERROR_LOG"
        exit 1
    fi
else
    echo "[$TIMESTAMP] primary_conninfo уже настроен в $SLAVE_CONF_FILE" >> "$LOG_FILE"
fi

# Копируем обновленный postgresql.conf в контейнер слейва
docker cp "$SLAVE_CONF_FILE" "$SLAVE_CONTAINER":/var/lib/postgresql/data/postgresql.conf 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Файл postgresql.conf скопирован в контейнер $SLAVE_CONTAINER" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при копировании postgresql.conf в $SLAVE_CONTAINER" >> "$ERROR_LOG"
    exit 1
fi

# 7. Копируем начальные данные с мастера на слейв (pg_basebackup)
echo "[$TIMESTAMP] Копирование данных с мастера на слейв..." >> "$LOG_FILE"
docker run --rm \
  -v "$SLAVE_DATA_DIR:/var/lib/postgresql/data" \
  "postgres:$POSTGRES_VERSION" \
  pg_basebackup -h "$MASTER_HOST" -p "$MASTER_PORT" -U "$REPLICA_USER" -D /var/lib/postgresql/data -P --wal-method=stream >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Данные успешно скопированы с мастера на слейв" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при копировании данных с мастера на слейв" >> "$ERROR_LOG"
    exit 1
fi

# 8. Перезапускаем слейв для применения настроек
echo "[$TIMESTAMP] Перезапуск контейнера $SLAVE_CONTAINER..." >> "$LOG_FILE"
docker restart "$SLAVE_CONTAINER" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Контейнер $SLAVE_CONTAINER успешно перезапущен" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при перезапуске $SLAVE_CONTAINER" >> "$ERROR_LOG"
    exit 1
fi

# 9. Проверка статуса репликации на мастере
echo "[$TIMESTAMP] Проверка статуса репликации на мастере..." >> "$LOG_FILE"
docker exec -t "$MASTER_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT * FROM pg_stat_replication;" >> "$LOG_FILE" 2>> "$ERROR_LOG"

if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Статус репликации успешно проверен" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при проверке статуса репликации" >> "$ERROR_LOG"
    exit 1
fi

echo "[$TIMESTAMP] Настройка репликации завершена!" >> "$LOG_FILE"
