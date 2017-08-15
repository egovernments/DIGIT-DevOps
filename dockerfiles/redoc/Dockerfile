FROM nginx

RUN apt-get update && apt-get install -y wget python

RUN mkdir /usr/share/nginx/html/redoc
COPY index.html /usr/share/nginx/html/redoc
