ARG PROD=false

FROM alpine:latest

RUN apk add --no-cache apache2 apache2-utils apache2-proxy apache2-ssl

WORKDIR /var/www/html

RUN if [ "$PROD" = "true" ]; then \
    cp /app/src /var/www/html; \
    fi

COPY /configs/apache/apache2.conf /etc/apache2/conf.d/

RUN chmod -Rf 777 /var/www/html

EXPOSE 80

CMD ["sh", "-c", "httpd -D FOREGROUND"]