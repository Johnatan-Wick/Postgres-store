#!/bin/bash

# Настройки
CONTAINER=postgres-master
DB_USER=postgres
DB_NAME=store_db
LOG_FILE=~/postgres-store/backups/monitor.log
ERROR_LOG=~/postgres-store/backups/backup_error.log
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)

# Создаем папку для логов, если она не существует
mkdir -p ~/postgres-store/backups

# Проверяем, что контейнер запущен
echo "[$TIMESTAMP] Проверка состояния контейнера $CONTAINER..." >> "$LOG_FILE"
docker ps | grep "$CONTAINER" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Контейнер $CONTAINER не запущен!" >> "$ERROR_LOG"
    exit 1
fi

# Проверяем, включен ли модуль pg_stat_statements
echo "[$TIMESTAMP] Проверка наличия модуля pg_stat_statements..." >> "$LOG_FILE"
docker exec -t "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements';" >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] Модуль pg_stat_statements не включен! Включите его в postgresql.conf и перезапустите контейнер." >> "$ERROR_LOG"
    exit 1
fi

# Выполнение запроса pg_stat_statements
echo "[$TIMESTAMP] Сбор статистики запросов..." >> "$LOG_FILE"
docker exec -t "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT query, calls, total_exec_time, rows
     FROM pg_stat_statements
     ORDER BY total_exec_time DESC
     LIMIT 5;" >> "$LOG_FILE" 2>> "$ERROR_LOG"

# Проверка статуса
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Статистика запросов записана" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при получении статистики" >> "$ERROR_LOG"
    exit 1
fi