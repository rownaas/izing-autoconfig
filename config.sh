#!/bin/bash

echo "Iniciando a configuração do ambiente..."

# Instalação de Nginx e Node.js
sudo apt update && sudo apt install nginx -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Instalação do PM2 globalmente
sudo npm install -g pm2@latest

# Configuração do PostgreSQL
sudo sed -i -e '/^#listen_addresses/s/^#//; s/listen_addresses = .*/listen_addresses = '\''*'\''/' /etc/postgresql/14/main/postgresql.conf
sudo sed -i 's/^host[[:space:]]*all[[:space:]]*all[[:space:]]*127\.0\.0\.1\/32.*/host all all 0.0.0.0\/0 md5/' /etc/postgresql/14/main/pg_hba.conf
sudo sed -i -e '/^# requirepass /s/^#//; s/requirepass .*/requirepass 2000@23/' /etc/redis/redis.conf

# Atualização da senha do usuário postgres e criação do banco de dados
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '2000@23';"
sudo -u postgres psql -c "CREATE DATABASE izing;"

# Configuração do RabbitMQ
sudo rabbitmqctl add_user admin 123456
sudo rabbitmqctl set_user_tags admin administrator
sudo rabbitmqctl set_permissions -p / admin "." "." ".*"

# Clone do repositório e limpeza
cd ~
git clone https://github.com/ldurans/izing.io.git
cd izing.io
sudo rm -rf /screenshots /.vscode .env.example
cd backend

# Configuração do arquivo .env
echo "Por favor, insira a URL do backend (exemplo: api.izing.com.br):"
read BACKEND_URL
echo "Por favor, insira a URL do frontend (exemplo: izing.com.br):"
read FRONTEND_URL

cat <<EOF >.env
NODE_ENV=dev
BACKEND_URL=https://$BACKEND_URL
FRONTEND_URL=https://$FRONTEND_URL
PROXY_PORT=443
PORT=8081
DB_DIALECT=postgres
DB_PORT=5432
POSTGRES_HOST=localhost
POSTGRES_USER=postgres
POSTGRES_PASSWORD=2000@23
POSTGRES_DB=izing
JWT_SECRET=DPHmNRZWZ4isLF9vXkMv1QabvpcA80Rc
JWT_REFRESH_SECRET=EMPehEbrAdi7s8fGSeYzqGQbV5wrjH4i
IO_REDIS_SERVER=127.0.0.1
IO_REDIS_PASSWORD=2000@23
IO_REDIS_PORT='6379'
IO_REDIS_DB_SESSION='2'
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=123456
AMQP_URL='amqp://admin:123456@localhost:5672?connection_attempts=5&retry_delay=5'
API_URL_360=https://waba-sandbox.360dialog.io
FACEBOOK_APP_ID=3237415623048660
FACEBOOK_APP_SECRET_KEY=3266214132b8c98ac59f3e957a5efeaaa13500
EOF

# Ajuste de dependências
sed -i 's/"whatsapp-web.js": "github:ldurans/whatsapp-web.js#webpack-exodus"/"whatsapp-web.js": "^1.23.0"/' ../package.json

# Instalação e construção do backend
sudo npm install
sudo npm run build
sudo npx sequelize db:migrate
sudo npx sequelize db:seed:all

# Preparação do frontend
cd ../frontend
sudo rm -rf .env.example
echo "VUE_URL_API='https://$FRONTEND_URL'" > .env
echo "VUE_FACEBOOK_APP_ID='23156312477653241'" >> .env

# Instalação e construção do frontend
sudo npm i -g @quasar/cli
sudo npm install
sudo quasar build -P -m pwa

# Preparação do PM2
sudo pm2 startup ubuntu -u root
sudo pm2 start ~/izing.io/backend/dist/server.js --name "izing-backend"

# Configuração do Nginx
sudo touch /etc/nginx/sites-available/$BACKEND_URL
sudo ln -s /etc/nginx/sites-available/$BACKEND_URL /etc/nginx/sites-enabled/
cat <<EOF >/etc/nginx/sites-available/$BACKEND_URL
server {
    listen 80;
    server_name $BACKEND_URL;
    return 301 https://$server_name$request_uri; # Redireciona HTTP para HTTPS
}

server {
    listen 443 ssl;
    server_name url;

    ssl_certificate /etc/ssl/certs/$BACKEND_URL.crt;
    ssl_certificate_key /etc/ssl/private/$BACKEND_URL.key;

    client_max_body_size 500M;

    location / {
        proxy_pass http://localhost:8081; # Ajuste a porta conforme necessário
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Configuração do Nginx
sudo touch /etc/nginx/sites-available/$FRONTEND_URL
sudo ln -s /etc/nginx/sites-available/$FRONTEND_URL /etc/nginx/sites-enabled/
cat <<EOF >/etc/nginx/sites-available/$FRONTEND_URL
server {
    listen 80;
    server_name $FRONTEND_URL;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name url;

    ssl_certificate /etc/ssl/certs/$FRONTEND_URL.crt;
    ssl_certificate_key /etc/ssl/private/$FRONTEND_URL.key;

    root /home/infoway/izing.open.io/frontend/dist/pwa;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        try_files $uri $uri/ =404;
        expires 1y;
        access_log off;
        add_header Cache-Control "public";
    }
}
EOF

# Configuração SSL
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/$BACKEND_URL.key -out /etc/ssl/certs/$BACKEND_URL.crt
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/$FRONTEND_URL.key -out /etc/ssl/certs/$FRONTEND_URL.crt

echo "Configuração concluída. Por favor, configure manualmente os arquivos de configuração do Nginx."

reboot
