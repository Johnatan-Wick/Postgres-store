# PostgreSQL Store Database

Этот проект разворачивает PostgreSQL в Docker для интернет-магазина с базой данных, 
резервным копированием, потоковой репликацией и мониторингом запросов.

## Требования

Для работы с проектом вам понадобятся:

- **Docker**: Установите Docker на вашем компьютере ([инструкция](https://docs.docker.com/get-docker/)).
- **Git**: Для клонирования репозитория ([инструкция](https://git-scm.com/downloads)).
- PostgreSQL-клиент (например, `psql`), если вы планируете выполнять запросы вручную.
- ОС: Проект протестирован на Linux/MacOS, но должен работать и на Windows с WSL2.

## Структура проекта

- `sql/` — SQL-скрипты:
  - `init.sql` — DDL для создания таблиц, индексов и связей.
  - `seed.sql` — Тестовые данные для имитации рабочей среды.
- `scripts/` — Скрипты автоматизации:
  - `backup.sh` — Создание резервных копий базы.
  - `cron_backup.sh` — Запуск резервного копирования (через `backup.sh`) с логированием для использования в cron.  - `monitor.sh` — Сбор статистики самых ресурсоемких SQL-запросов через `pg_stat_statements`.
  - `replication.sh` — Настройка потоковой репликации между мастером и слейвом.
- `config/` — Конфигурационные файлы PostgreSQL (например, `postgresql.conf`, `pg_hba.conf`).
- `Dockerfile` — Настройка Docker-образа PostgreSQL.
- `backups/`, `master-data/`, `slave-data/` — Данные и бэкапы (не в Git).

## Установка и запуск

## 1. Склонируйте репозиторий:
   ```bash
   git clone <your-repo-url>
   cd Postgres-Admin-Tools
   ```
   
## 2. Запустите мастер и слейв, а затем настройте репликацию:
   ```bash
    ./Postgres-Admin-Tools/scripts/start_all.sh
   ```
 
## 3. Убедитесь, что конфигурация репликации настроена.
  Запустите скрипт для настройки репликации:
  ```bash
  ./scripts/replication.sh
  ```

  * Скрипт создает пользователя replica_user на мастере, настраивает postgresql.conf и pg_hba.conf мастера. 
  * Cоздает файл standby.signal в slave-data/.
  * Kопирует начальные данные с мастера на слейв с помощью pg_basebackup,и настраивает подключение слейва к мастеру. 
  * Логи записываются в ~/postgres-store/backups/replication.log, 
  * Oшибки — в ~/postgres-store/backups/backup_error.log. 

## 4. Для проверки репликации выполните на мастере:
   ```bash
    docker exec -t postgres-master psql -U postgres -d store_db -c "SELECT * FROM pg_stat_replication;"
   ```
 * Репликация Потоковая репликация настроена между postgres-master (порт 5434) и postgres-slave (порт 5435). 
 * Скрипт replication.sh настраивает мастера (пользователь replica_user, postgresql.conf, pg_hba.conf). 
 * Cоздает файл standby.signal в slave-data/.
 * Kопирует данные с мастера на слейв с помощью pg_basebackup, и настраивает primary_conninfo на слейве.
     

## 5. Резервное копирование.Выполните скрипт для создания бэкапа:
   ```bash
    ./scripts/backup.sh
   ```
 * Скрипт создает SQL-дамп базы и полный бэкап с помощью pg_basebackup.
 * SQL-дампы сохраняются в backups/, полный бэкап — в slave-data/.
 * Старые дампы (старше 3 дней) автоматически удаляются.
 * Логи записываются в ~/postgres-store/backups/backup.log.
 * Oшибки — в ~/postgres-store/backups/backup_error.log.
   
## 6. Для автоматического резервного копирования используйте `cron_backup.sh`. См. раздел "Примеры использования".

## 7. Мониторинг запросов включён через pg_stat_statements. Проверьте статистику:
   ```bash 
   docker exec -it postgres-master psql -U postgres -d store_db -c "SELECT query, calls, total_exec_time FROM 
   pg_stat_statements ORDER BY total_exec_time DESC LIMIT 5;"
   ```


## Примеры использования

## 1. Добавление данных: После запуска контейнеров добавьте тестовые данные:
   ```bash 
   docker exec -it postgres-master psql -U postgres -d store_db -f /sql/seed.sql
   ```
## 2. Проверка данных: Посмотрите список пользователей:  
   ```bash
   docker exec -it postgres-master psql -U postgres -d store_db -c "SELECT * FROM users LIMIT 5;"
   ```
## 3. Создание резервной копии: Выполните скрипт для создания бэкапа:
   ```bash
    ./scripts/backup.sh
   ```
 * Скрипт создает SQL-дамп базы и полный бэкап с помощью pg_basebackup.
 * SQL-дампы сохраняются в backups/, полный бэкап — в slave-data/.
 * Старые дампы (старше 3 дней) автоматически удаляются.
 * Логи записываются в ~/postgres-store/backups/backup.log.
 * Oшибки — в ~/postgres-store/backups/backup_error.log.

## 4. Автоматическое резервное копирование,настройте cron для регулярного бэкапа:
   ```bash
   crontab -e
   ```
 * Скрипт `cron_backup.sh` вызывает `backup.sh` для создания резервных копий (SQL-дамп и полный бэкап). 
 * Логи записываются в `~/postgres-store/backups/cron_backup.log`.
 * Oшибки — в `~/postgres-store/backups/backup_error.log`.

## 5. Добавьте строку для запуска cron_backup.sh каждую ночь в 2:00:
   ```bash
   0 2 * * * /path/to/postgres-store/scripts/cron_backup.sh
   ```
## Конфигурация

### Основная база (мастер):
  * Файлы: config/master/postgresql.conf, config/master/pg_hba.conf.
   * Ключевые параметры:
     * listen_addresses = '*' — Разрешить подключения извне.
     * wal_level = replica — Для репликации.
     * max_wal_senders = 3 — Количество слейвов.
### Подчиненная база (слейв):
  * Файлы: config/slave/postgresql.conf, config/slave/pg_hba.conf, slave-data/standby.signal.
   * Ключевые параметры:
     * hot_standby = on — Разрешить чтение на слейве.
     *  В standby.signal указывает, что сервер работает в режиме реплики.

## Структура базы данных

### База store_db включает таблицы:
* `users` — Пользователи.
* `products` — Товары.
* `orders` — Заказы.
* `order_items` — Элементы заказов. 
  * Подробности в sql/init.sql


## Устранение неполадок

### 1. Ошибка подключения к мастеру или слейву:
   * Убедитесь, что порты 5434 (мастер) и 5435 (слейв) не заняты другими процессами.
   * Проверьте настройки в config/master/pg_hba.conf и config/slave/pg_hba.conf.

### 2.  Репликация не работает:
   * Убедитесь, что файл standby.signal присутствует в slave-data/.
   * Проверьте логи мастера:
     ```bash 
      docker logs postgres-master
     ```
### 3. Проверьте логи репликации в ~/postgres-store/backups/replication.log.

### 4. Мониторинг не показывает данные:
   * Убедитесь, что модуль pg_stat_statements включен в postgresql.conf:
   ```bash 
     shared_preload_libraries = 'pg_stat_statements'
   ```
### 5. Перезапустите контейнер после изменения конфигурации:
  ```bash
     docker restart postgres-master
  ```
