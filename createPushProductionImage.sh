SRC_DIR="app/src"
PROVIDE_DOCKER_COMPOSE="false"

if [ -d "$SRC_DIR/node_modules" ] && [ -d "$SRC_DIR/vendor" ]; then
    read -p "Are node_modules and vendor folders 100% up to date? (y/n): " confirmation
    if [ "$confirmation" != "y" ]; then
        echo "Please update node_modules and vendor folders before proceeding."
        exit 1
    fi
else
    echo "Either node_modules or vendor folder is missing in $SRC_DIR."
    exit 1
fi

read -p "Do you want to be provided with a custom docker-compose.yml file for accessing the production image once it has been pushed? (DISCLAIMER - You may need to make changes to it based on the platform being using to host it!) (y/n): " confirmation
 if [ "$confirmation" = "y" ]; then
   PROVIDE_DOCKER_COMPOSE="true"
 fi

read -p "Enter name of docker deployment environment (dockerDeployment by default): " docker_environment_name

read -p "Enter Docker Username: " docker_username

read -p "Enter image tag: " image_tag

cd "./$SRC_DIR"

if [ -d "$SRC_DIR/node_modules" ]; then
    echo "Removing node_modules requires elevated permissions."
    sudo rm -rf "$SRC_DIR/node_modules"
fi

### Replace lines with #BOOT comment attached if youre using https, as otherwise http will be forced

# BOOT
APP_SERVICE_PROVIDER="/var/www/html/$docker_environment_name/$SRC_DIR/app/Providers/AppServiceProvider.php"
ORIGINAL_APP_SERVICE_PROVIDER="$APP_SERVICE_PROVIDER.bak"

# BOOT
cp "$APP_SERVICE_PROVIDER" "$ORIGINAL_APP_SERVICE_PROVIDER"


# BOOT
sed -i "/public function boot()/, /}/c\
public function boot(): void {\n\
    if (config('app.env') === 'production') {\n\
        URL::forceScheme('http');\n\
    }\n\
" "$APP_SERVICE_PROVIDER"


BUILD_KEY="build"
PACKAGE_JSON="/var/www/html/$docker_environment_name/$SRC_DIR/package.json"
ORIGINAL_BUILD_COMMAND=$(grep -oP '"build"\s*:\s*"\K[^"]+' "$PACKAGE_JSON")  # Read the original "build" command

sed -i.bak -E "s|(\"build\":\s*\")[^\"]+|\1npx vite build --mode production|" "$PACKAGE_JSON"

cd ../..

echo "Building Docker images with tag $image_tag..."
docker build --build-arg PROD=true --no-cache -t $docker_username/apache-prod:$image_tag -f apache-custom/Dockerfile .
docker build --build-arg PROD=true --no-cache -t $docker_username/node-prod:$image_tag -f node-custom/Dockerfile .
docker build --build-arg PROD=true --no-cache -t $docker_username/php-fpm-prod:$image_tag -f php-fpm-custom/Dockerfile .
docker build --build-arg PROD=true --no-cache -t $docker_username/php-cli-prod:$image_tag -f php-cli-custom/Dockerfile .

if [ $? -ne 0 ]; then
    echo "Error building Docker images. Please check the logs and try again."
    # BOOT
    cp "$ORIGINAL_APP_SERVICE_PROVIDER" "$APP_SERVICE_PROVIDER"
    exit 1
fi

# BOOT
cp "$ORIGINAL_APP_SERVICE_PROVIDER" "$APP_SERVICE_PROVIDER"

sed -i -E "s|(\"build\":\s*\")[^\"]+|\1${ORIGINAL_BUILD_COMMAND}|" "$PACKAGE_JSON"

echo "Tagging and pushing images to Docker Hub for user $docker_username..."
docker push $docker_username/apache-prod:$image_tag
docker push $docker_username/node-prod:$image_tag
docker push $docker_username/php-fpm-prod:$image_tag
docker push $docker_username/php-cli-prod:$image_tag

if [ $? -ne 0 ]; then
    echo "Error pushing images to Docker Hub. Please check your Docker credentials and try again."
    exit 1
fi

echo "Docker images built and pushed successfully!"

if [ "$PROVIDE_DOCKER_COMPOSE" = "true" ]; then
    echo "Generating custom docker-compose.prod.yml file..."
    cat <<EOL > docker-compose.prod.yml
services:

  apache:
    image: $docker_username/apache-prod:$image_tag
    volumes:
      - app_data:/var/www/html
    ports:
      - "80:80"
    depends_on:
      - php-fpm
    restart: always

  php-fpm:
    image: $docker_username/php-fpm-prod:$image_tag
    volumes:
      - app_data:/var/www/html
    depends_on:
      - node

  php-cli:
    image: $docker_username/php-cli-prod:$image_tag
    volumes:
      - app_data:/var/www/html
    command: tail -f /dev/null
    depends_on:
      - node

  node:
    image: $docker_username/node-prod:$image_tag
    volumes:
      - app_data:/var/www/volume
    command: sh -c "rsync -a --delete /var/www/html/ /var/www/volume && cd /var/www/volume && npm install && npm run build && tail -f /dev/null"
    ports:
      - "5173:5173"

  mysql:
    image: mysql
    volumes:
      - database_data:/var/lib/mysql
      - ./init:/docker-entrypoint-initdb.d
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: deployment_db
      MYSQL_USER: admin
      MYSQL_PASSWORD: adminpassword
    ports:
      - "3306:3306"

  phpmyadmin:
    image: phpmyadmin
    environment:
      PMA_HOST: mysql
      PMA_PORT: 3306
      PMA_USER: admin
      PMA_PASSWORD: adminpassword
    ports:
      - "8080:80"
    depends_on:
      - mysql

volumes:
  database_data:
  app_data:
EOL
    echo "docker-compose.prod.yml file has been generated."
fi
