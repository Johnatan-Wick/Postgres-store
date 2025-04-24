#!/bin/bash

# Запускаем мастер
docker run -d --name postgres-master -p 5434:5432 -v $(pwd)/master-data:/var/lib/postgresql/data postgres-store

# Запускаем слейв
docker run -d --name postgres-slave -p 5435:5432 -v $(pwd)/slave-data:/var/lib/postgresql/data --link postgres-master postgres-store

# Ждем, пока контейнеры запустятся
echo "Ожидание запуска контейнеров..."
sleep 5

# Запускаем настройку репликации
echo "Настройка репликации..."
./scripts/replication.sh