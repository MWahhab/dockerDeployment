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

read -p "Do you want to be provided with a custom docker-compose.yml file for accessing the production application once it has been pushed? (DISCLAIMER - You may need to make changes to it based on the platform being using to host it!) (y/n): " confirmation
 if [ "$confirmation" = "y" ]; then
   PROVIDE_DOCKER_COMPOSE="true"
 fi

read -p "Are you hosting this production application using HTTPS? (y/n): " isHostingUsingHttps

if [ "$isHostingUsingHttps" = "y" ]; then
  read -p "Since you're using HTTPS, please provide the URL that you will be used : " HTTPSURL
fi

read -p "Do you want to specify a platform? (y/n): " changePlatform

if [ "$changePlatform" = "y" ]; then
  read -p "Please enter the platform. (e.g: linux/arm64): " platformForBuild
fi

read -p "Enter Docker Username: " docker_username

read -p "Enter image tag: " image_tag

if [ "$isHostingUsingHttps" = "y" ]; then
  #updating APP_URL in the .env file to https url
  ENV_FILE="app/prod-stash/.env"
  if [ -f "./$ENV_FILE" ]; then
    ORIGINAL_APP_URL=$(grep -E '^APP_URL=' "./$ENV_FILE" | cut -d '=' -f2)
    sed -i.bak -E "s|^APP_URL=.*|APP_URL=$HTTPSURL|" "./$ENV_FILE"
    echo "APP_URL temporarily updated to $HTTPSURL in ./$ENV_.FILE."
  else
    echo "No .env file found in prod-stash directory."
  fi
fi

cd "./$SRC_DIR"

if [ -d "$SRC_DIR/node_modules" ]; then
    echo "Removing node_modules requires elevated permissions."
    sudo rm -rf "$SRC_DIR/node_modules"
fi

if [ "$isHostingUsingHttps" != "y" ]; then
  #im forcing http here, so there arent issues with fetching the assets in the "public/build" dir. attempts to fetch using https otherwise!
  APP_SERVICE_PROVIDER="app/Providers/AppServiceProvider.php"
  ORIGINAL_APP_SERVICE_PROVIDER="$APP_SERVICE_PROVIDER.bak"

  cp "$APP_SERVICE_PROVIDER" "$ORIGINAL_APP_SERVICE_PROVIDER"

  sed -i "/public function boot()/, /}/c\
  public function boot(): void {\n\
      if (config('app.env') === 'production') {\n\
          URL::forceScheme('http');\n\
      }\n\
  " "$APP_SERVICE_PROVIDER"
fi

#reading the original build command so i can change it to npx vite build --mode production
BUILD_KEY="build"
PACKAGE_JSON="package.json"
ORIGINAL_BUILD_COMMAND=$(grep -oP '"build"\s*:\s*"\K[^"]+' "$PACKAGE_JSON")

sed -i.bak -E "s|(\"build\":\s*\")[^\"]+|\1npx vite build --mode production|" "$PACKAGE_JSON"

cd ../..

echo "Building Docker images with tag $image_tag..."

if [ "$changePlatform" = "y" ]; then
    echo "Using platform $platformForBuild for Docker builds."
    docker build --build-arg PROD=true --no-cache --platform "$platformForBuild" -t $docker_username/apache-prod:$image_tag -f apache-custom/Dockerfile .
    docker build --build-arg PROD=true --no-cache --platform "$platformForBuild" -t $docker_username/node-prod:$image_tag -f node-custom/Dockerfile .
    docker build --build-arg PROD=true --no-cache --platform "$platformForBuild" -t $docker_username/php-fpm-prod:$image_tag -f php-fpm-custom/Dockerfile .
    docker build --build-arg PROD=true --no-cache --platform "$platformForBuild" -t $docker_username/php-cli-prod:$image_tag -f php-cli-custom/Dockerfile .
else
    docker build --build-arg PROD=true --no-cache -t $docker_username/apache-prod:$image_tag -f apache-custom/Dockerfile .
    docker build --build-arg PROD=true --no-cache -t $docker_username/node-prod:$image_tag -f node-custom/Dockerfile .
    docker build --build-arg PROD=true --no-cache -t $docker_username/php-fpm-prod:$image_tag -f php-fpm-custom/Dockerfile .
    docker build --build-arg PROD=true --no-cache -t $docker_username/php-cli-prod:$image_tag -f php-cli-custom/Dockerfile .
fi

if [ $? -ne 0 ]; then
    echo "Error building Docker images. Please check the logs and try again."
    cp "$ORIGINAL_APP_SERVICE_PROVIDER" "$APP_SERVICE_PROVIDER"
    exit 1
fi

if [ "$isHostingUsingHttps" = "y" ]; then
  cp "$ENV_FILE.bak" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
fi

cd app/src

if [ "$isHostingUsingHttps" != "y" ]; then
  cp "$ORIGINAL_APP_SERVICE_PROVIDER" "$APP_SERVICE_PROVIDER"
  rm -f "$APP_SERVICE_PROVIDER.bak"
fi

sed -i -E "s|(\"build\":\s*\")[^\"]+|\1${ORIGINAL_BUILD_COMMAND}|" "$PACKAGE_JSON"
rm -f "$PACKAGE_JSON.bak"

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
EOL
    if [ "$changePlatform" = "y" ]; then
        echo "    platform: $platformForBuild" >> docker-compose.prod.yml
    fi

    cat <<EOL >> docker-compose.prod.yml

  php-fpm:
    image: $docker_username/php-fpm-prod:$image_tag
    volumes:
      - app_data:/var/www/html
    depends_on:
      - node
EOL
    if [ "$changePlatform" = "y" ]; then
        echo "    platform: $platformForBuild" >> docker-compose.prod.yml
    fi

    cat <<EOL >> docker-compose.prod.yml

  php-cli:
    image: $docker_username/php-cli-prod:$image_tag
    volumes:
      - app_data:/var/www/html
    command: tail -f /dev/null
    depends_on:
      - node
EOL
    if [ "$changePlatform" = "y" ]; then
        echo "    platform: $platformForBuild" >> docker-compose.prod.yml
    fi

    cat <<EOL >> docker-compose.prod.yml

  node:
    image: $docker_username/node-prod:$image_tag
    volumes:
      - app_data:/var/www/volume
    command: sh -c "rsync -a --delete /var/www/html/ /var/www/volume && cd /var/www/volume && npm install && npm run build && tail -f /dev/null"
    ports:
      - "5173:5173"
EOL
    if [ "$changePlatform" = "y" ]; then
        echo "    platform: $platformForBuild" >> docker-compose.prod.yml
    fi

    cat <<EOL >> docker-compose.prod.yml

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
