FROM node:alpine

RUN apk add --no-cache rsync

WORKDIR /var/www/html

COPY /app/src /var/www/html
COPY /app/prod-stash/vite.config.js /var/www/html/vite.config.js
COPY /app/prod-stash/.env /var/www/html/.env
RUN rm -f /var/www/html/public/hot
RUN rm -rf /var/www/html/storage/framework/views/*

RUN chmod -Rf 777 /var/www/html