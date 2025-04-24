#!/bin/bash

# Настройки
BACKUP_SCRIPT=~/postgres-store/scripts/backup.sh
LOG_FILE=~/postgres-store/backups/cron_backup.log
ERROR_LOG=~/postgres-store/backups/backup_error.log
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)

# Создаем папку для логов, если она не существует
mkdir -p ~/postgres-store/backups

# Проверка существования backup.sh
if [ ! -f "$BACKUP_SCRIPT" ]; then
    echo "[$TIMESTAMP] Ошибка: $BACKUP_SCRIPT не найден" >> "$ERROR_LOG"
    exit 1
fi

# Выполнение backup.sh
echo "[$TIMESTAMP] Запуск backup.sh..." >> "$LOG_FILE"
bash "$BACKUP_SCRIPT" >> "$LOG_FILE" 2>> "$ERROR_LOG"

# Проверка статуса выполнения
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Бэкап успешно выполнен" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Ошибка при выполнении бэкапа" >> "$ERROR_LOG"
    exit 1
fi