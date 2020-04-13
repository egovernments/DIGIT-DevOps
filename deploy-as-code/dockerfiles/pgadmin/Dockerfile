FROM dpage/pgadmin4:4.1

COPY ./initialize_db_server.sh /opt/pgadmin/initialize_db_server.sh

COPY ./init.py /opt/pgadmin/init.py

RUN \
    apk add --no-cache sqlite && \
    chmod +x /opt/pgadmin/initialize_db_server.sh && \
    # re rely on the current entrypoint.sh impl
    sed -i '/python run_pgadmin.py/a   \/opt\/pgadmin\/initialize_db_server.sh' /entrypoint.sh 
