#!/bin/bash

docker-entrypoint.sh postgres &

echo "Ожидание запуска PostgreSQL..."
until pg_isready -h localhost -p 5432 -U postgres; do
    sleep 1
done

echo "Запуск скриптов..."

/scripts/replication.sh &

/scripts/monitor.sh &


wait