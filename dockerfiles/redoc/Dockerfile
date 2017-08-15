FROM nginx

RUN apt-get update && apt-get install -y python cron

RUN mkdir /usr/share/nginx/html/redoc
RUN mkdir /opt/eGov
COPY ./update_redoc_html.py /opt/eGov/
COPY crontab /etc/cron.d/update_redoc_html
RUN chmod 0644 /etc/cron.d/update_redoc_html
COPY ./index.html /usr/share/nginx/html/redoc/
COPY ./start.sh /usr/local/bin/start.sh
RUN chmod a+x /usr/local/bin/start.sh
CMD ["/usr/local/bin/start.sh"]
