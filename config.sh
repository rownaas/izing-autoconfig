#!/bin/bash

echo "Iniciando a configuração do ambiente..."

sudo timedatectl set-local-rtc 0
sudo systemctl restart systemd-timesyncd

# Instalação de Nginx e Node.js
sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt install nginx -y
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo DEBIAN_FRONTEND=noninteractive -E bash -
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

sudo timedatectl set-timezone America/Sao_Paulo && \
sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y && \
sudo DEBIAN_FRONTEND=noninteractive apt install -y npm libgbm-dev wget unzip fontconfig locales gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils python2-minimal build-essential && \
sudo DEBIAN_FRONTEND=noninteractive apt install -y postgresql redis-server && \ 
sudo add-apt-repository -y ppa:rabbitmq/rabbitmq-erlang && \
wget -qO - https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh | sudo bash && \
sudo DEBIAN_FRONTEND=noninteractive apt install -y rabbitmq-server && \
sudo rabbitmq-plugins enable rabbitmq_management && \
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
sudo DEBIAN_FRONTEND=noninteractive apt install -y ./google-chrome-stable_current_amd64.deb && \
sudo rm -rf google-chrome-stable_current_amd64.deb

# Instalação do PM2 globalmente
sudo npm install -g pm2@latest

# Configuração do PostgreSQL
sudo sed -i -e '/^#listen_addresses/s/^#//; s/listen_addresses = .*/listen_addresses = '\''*'\''/' /etc/postgresql/14/main/postgresql.conf
sudo sed -i 's/^host[[:space:]]*all[[:space:]]*all[[:space:]]*127\.0\.0\.1\/32.*/host    all             all             0.0.0.0\/0               scram-sha-256/' /etc/postgresql/14/main/pg_hba.conf
sudo sed -i -e '/^# requirepass /s/^#//; s/requirepass .*/requirepass 2000@23/' /etc/redis/redis.conf

# Atualização da senha do usuário postgres e criação do banco de dados
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
sudo -u postgres psql -c "CREATE DATABASE izing;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE izing TO postgres;"

# Configuração do RabbitMQ
sudo rabbitmqctl add_user admin 123456
sudo rabbitmqctl set_user_tags admin administrator
sudo rabbitmqctl set_permissions -p / admin "." "." ".*"

# Clone do repositório e limpeza
cd /home/infoway/
git clone https://github.com/ldurans/izing.io.git
cd izing.io
sudo rm -rf screenshots .vscode .env.example Makefile package.json package-lock.json README.md CHANGELOG.md  donate.jpeg
cd backend
rm -rf package-lock.json

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

POSTGRES_HOST=127.0.0.1
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
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
sudo sed -i -e 's|"whatsapp-web.js": "github:ldurans/whatsapp-web.js#webpack-exodus"|"whatsapp-web.js": "^1.23.0"|' package.json

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
cd dist/
sudo cp -rf pwa pwa.bkp

# Preparação do PM2
sudo pm2 startup ubuntu -u root
sudo pm2 start /home/infoway/izing.io/backend/dist/server.js --name "izing-backend"




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

CONFIG_FILE="req.conf"
KEY_FILE="/etc/ssl/private/$BACKEND_URL.key"
CERT_FILE="/etc/ssl/certs/$BACKEND_URL.crt"

cat > $CONFIG_FILE <<EOF
[req]
prompt = no
distinguished_name = dn

[dn]
C=SC
ST=Infoway
L=Blumenau
O=Infoway
OU=INF
CN=Infoway
emailAddress=teste@gmail.com
EOF

sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -config $CONFIG_FILE
sudo rm $CONFIG_FILE


# Configuração SSL

CONFIG_FILE="req.conf"
KEY_FILE="/etc/ssl/private/$FRONTEND_URL.key"
CERT_FILE="/etc/ssl/certs/$FRONTEND_URL.crt"

# Criando o arquivo de configuração
cat > $CONFIG_FILE <<EOF
[req]
prompt = no
distinguished_name = dn

[dn]
C=SC
ST=Infoway
L=Blumenau
O=Infoway
OU=INF
CN=Infoway
emailAddress=teste@gmail.com
EOF

# Executando o comando OpenSSL
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -config $CONFIG_FILE

# Excluindo o arquivo de configuração
sudo rm $CONFIG_FILE




echo "Configuração concluída. Por favor, configure manualmente os arquivos de configuração do Nginx."

sudo reboot
