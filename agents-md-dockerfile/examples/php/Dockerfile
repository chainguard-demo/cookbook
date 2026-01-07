FROM php:8.3

RUN apt-get update && apt-get install -y \
    git \
    curl \
    libxml2-dev \
    zip \
    unzip \
    pkg-config \
    ssh \
    uuid-runtime

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

WORKDIR /app
COPY . /app

# set up nonroot system user
RUN useradd -r -s /bin/bash nonroot && \
    chown -R nonroot /app && \
    cd /app && composer install

USER nonroot
CMD [ "php", "index.php"]
