FROM postgres:latest

# Копируем конфигурационные файлы
COPY config/master/postgresql.conf /etc/postgresql/postgresql.conf
COPY config/master/pg_hba.conf /etc/postgresql/pg_hba.conf

# Копируем скрипты
COPY scripts /scripts

# Копируем entrypoint.sh
COPY entrypoint.sh /entrypoint.sh

# Делаем скрипты исполняемыми
RUN chmod +x /entrypoint.sh /scripts/*.sh

# Устанавливаем entrypoint
ENTRYPOINT ["/entrypoint.sh"]