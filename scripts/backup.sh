#!/bin/bash

# Настройки
export PATH=/usr/local/bin:/usr/bin:/bin
BACKUP_DIR=~/postgres-store/backups
SLAVE_DATA_DIR=~/postgres-store/slave-data
LOG_FILE=~/postgres-store/backups/backup.log
ERROR_LOG=~/postgres-store/backups/backup_error.log
CONTAINER=postgres-master
DB_USER=postgres
DB_NAME=store_db
REPLICA_USER=replica_user
REPLICA_HOST=localhost
REPLICA_PORT=5434
POSTGRES_VERSION=17
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)

# Создание директорий
mkdir -p "$BACKUP_DIR" "$SLAVE_DATA_DIR"

# Проверяем, что контейнер запущен
echo "[$TIMESTAMP] Проверка состояния контейнера $CONTAINER..." >> "$LOG_FILE"
docker ps | grep "$CONTAINER" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Контейнер $CONTAINER не запущен!" >> "$ERROR_LOG"
    exit 1
fi

# Проверяем пользователя репликации
echo "[$TIMESTAMP] Проверка пользователя репликации $REPLICA_USER..." >> "$LOG_FILE"
docker exec -t "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT 1 FROM pg_roles WHERE rolname='$REPLICA_USER';" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Пользователь $REPLICA_USER не существует или не имеет прав на репликацию!" >> "$ERROR_LOG"
    exit 1
fi

# Создание SQL-дампа
echo "[$TIMESTAMP] Создание SQL-дампа..." >> "$LOG_FILE"
docker exec -t "$CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql" 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] SQL-дамп успешно создан" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при создании SQL-дампа" >> "$ERROR_LOG"
    exit 1
fi

# Очистка slave-data
echo "[$TIMESTAMP] Очистка $SLAVE_DATA_DIR..." >> "$LOG_FILE"
rm -rf "$SLAVE_DATA_DIR"/* 2>> "$ERROR_LOG"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] $SLAVE_DATA_DIR успешно очищена" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при очистке $SLAVE_DATA_DIR" >> "$ERROR_LOG"
    exit 1
fi

# Создание полного бэкапа с pg_basebackup
echo "[$TIMESTAMP] Создание полного бэкапа с pg_basebackup..." >> "$LOG_FILE"
docker run --rm \
  -v "$SLAVE_DATA_DIR:/var/lib/postgresql/data" \
  "postgres:$POSTGRES_VERSION" \
  pg_basebackup -h "$REPLICA_HOST" -p "$REPLICA_PORT" -U "$REPLICA_USER" -D /var/lib/postgresql/data -P --wal-method=stream >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Полный бэкап успешно создан в $SLAVE_DATA_DIR" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при создании полного бэкапа" >> "$ERROR_LOG"
    exit 1
fi

# Удаление старых SQL-дампов (старше 3 дней)
echo "[$TIMESTAMP] Удаление старых SQL-дампов (старше 3 дней)..." >> "$LOG_FILE"
find "$BACKUP_DIR" -name "backup_*.sql" -mtime +3 -delete
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Старые дампы успешно удалены" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при удалении старых дампов" >> "$ERROR_LOG"
    exit 1
fi