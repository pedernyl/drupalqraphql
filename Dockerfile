FROM drupal:10

# Install curl, nano, git and unzip
RUN apt-get update && apt-get install -y \
    curl \
    nano \
    git \
    unzip \
    wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Composer globally
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set working directory
WORKDIR /opt/drupal

COPY composer.json composer.lock ./

RUN composer install --no-dev --optimize-autoloader

COPY . . 

WORKDIR /opt/drupal/web
  