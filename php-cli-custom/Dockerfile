FROM php:cli-alpine

ARG PROD=false

RUN apk add --no-cache git unzip $PHPIZE_DEPS libjpeg-turbo-dev libpng-dev && \
    docker-php-ext-install pdo pdo_mysql && \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN if [ "$PROD" = "false" ]; then \
    apk add --no-cache linux-headers && \
    pecl install xdebug && \
    docker-php-ext-enable xdebug && \
    apk del linux-headers;\
    fi

RUN apk del $PHPIZE_DEPS;

WORKDIR /var/www/html

COPY /configs/xdebug/xdebug.ini /configs/xdebug/xdebug.ini

RUN if [ "$PROD" = "false" ]; then \
    #Path to local .ini file is like so - as "docker build" is ran using root as build context
    cp /configs/xdebug/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini; \
    fi

RUN rm -f /configs/xdebug/xdebug.ini

RUN chmod -Rf 777 /var/www/html