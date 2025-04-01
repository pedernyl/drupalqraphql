FROM drupal:10

# Install curl, nano, git and unzip
RUN apt-get update && apt-get install -y \
    curl \
    nano \
    git \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

 # Set working directory
WORKDIR /var/www/html   