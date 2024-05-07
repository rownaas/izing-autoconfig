#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Uso: $0 BACKEND_URL FRONTEND_URL"
    exit 1
fi

BACKEND_URL=$1
FRONTEND_URL=$2

LOGFILE="/var/log/configuracao_ambiente.log"
echo "Iniciando a configuração do ambiente..." | tee -a $LOGFILE

timedatectl set-local-rtc 0 | tee -a $LOGFILE
systemctl restart systemd-timesyncd | tee -a $LOGFILE

# Instalação do Node.js 14.21.1 usando NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
nvm install 18
nvm install 16
nvm use 18

# Configurações regionais e de horário
timedatectl set-timezone America/Sao_Paulo && \
DEBIAN_FRONTEND=noninteractive apt update && \
DEBIAN_FRONTEND=noninteractive apt upgrade -y | tee -a $LOGFILE

# Instalação de dependências de software
DEBIAN_FRONTEND=noninteractive apt install -y libgbm-dev wget unzip fontconfig locales \
gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 \
libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 \
libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 \
libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release \
xdg-utils python2-minimal build-essential postgresql redis-server libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev | tee -a $LOGFILE

# Instalacao do nginx
wget http://nginx.org/download/nginx-1.21.0.tar.gz
tar -zxvf nginx-1.21.0.tar.gz
cd nginx-1.21.0/
./configure
make
make install

# Configuração do RabbitMQ
add-apt-repository -y ppa:rabbitmq/rabbitmq-erlang | tee -a $LOGFILE && \
wget -qO - https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh |  bash && \
DEBIAN_FRONTEND=noninteractive apt install -y rabbitmq-server | tee -a $LOGFILE && \
rabbitmq-plugins enable rabbitmq_management | tee -a $LOGFILE

# Instalação do Google Chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb | tee -a $LOGFILE && \
DEBIAN_FRONTEND=noninteractive apt install -y ./google-chrome-stable_current_amd64.deb | tee -a $LOGFILE && \
rm google-chrome-stable_current_amd64.deb | tee -a $LOGFILE

# Instalação do PM2 globalmente
echo "Instalando o pm2: " | tee -a $LOGFILE
npm install -g pm2@5.1 | tee -a $LOGFILE
echo "IFinalizou o pm2." | tee -a $LOGFILE
npm install -g typescript | tee -a $LOGFILE

# Configuração do PostgreSQL
sed -i -e '/^#listen_addresses/s/^#//; s/listen_addresses = .*/listen_addresses = '\''*'\''/' /etc/postgresql/14/main/postgresql.conf | tee -a $LOGFILE
sed -i 's/^host[[:space:]]*all[[:space:]]*all[[:space:]]*127\.0\.0\.1\/32.*/host    all             all             0.0.0.0\/0               scram-sha-256/' /etc/postgresql/14/main/pg_hba.conf | tee -a $LOGFILE
sed -i -e '/^# requirepass /s/^#//; s/requirepass .*/requirepass redis/' /etc/redis/redis.conf | tee -a $LOGFILE

# Atualização da senha do usuário postgres e criação do banco de dados
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';" | tee -a $LOGFILE
sudo -u postgres psql -c "CREATE DATABASE izing;" | tee -a $LOGFILE

# Configuração do RabbitMQ
rabbitmqctl add_user admin 123456 | tee -a $LOGFILE
rabbitmqctl set_user_tags admin administrator | tee -a $LOGFILE
rabbitmqctl set_permissions -p / admin "." "." ".*" | tee -a $LOGFILE

# Clone do repositório e limpeza
cd /home/infoway/
git clone https://github.com/ldurans/izing.io.git
cd izing.io
rm -rf screenshots .vscode .env.example Makefile package.json package-lock.json README.md CHANGELOG.md  donate.jpeg 
cd backend
rm -rf package-lock.json

cat <<EOF >.env
# ambiente
NODE_ENV=dev

# URL do backend para construção dos hooks
BACKEND_URL=https://$BACKEND_URL

# URL do front para liberação do cors
FRONTEND_URL=https://$FRONTEND_URL

# Porta utilizada para proxy com o serviço do backend
PROXY_PORT=443

# Porta que o serviço do backend deverá ouvir
PORT=8081

# conexão com o banco de dados
DB_DIALECT=postgres
DB_PORT=5432
POSTGRES_HOST=localhost
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=izing

# Chaves para criptografia do token jwt
JWT_SECRET=DPHmNRZWZ4isLF9vXkMv1QabvpcA80Rc
JWT_REFRESH_SECRET=EMPehEbrAdi7s8fGSeYzqGQbV5wrjH4i

# Dados de conexão com o REDIS
IO_REDIS_SERVER=127.0.0.1
IO_REDIS_PORT='6379'
IO_REDIS_DB_SESSION='2'
IO_REDIS_PASSWORD=redis

CHROME_BIN=/usr/bin/google-chrome-stable

MIN_SLEEP_BUSINESS_HOURS=1000
MAX_SLEEP_BUSINESS_HOURS=2000

MIN_SLEEP_AUTO_REPLY=400
MAX_SLEEP_AUTO_REPLY=600

MIN_SLEEP_INTERVAL=200
MAX_SLEEP_INTERVAL=500

# dados do RabbitMQ / Para não utilizar, basta comentar a var AMQP_URL
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=123456
AMQP_URL='amqp://admin:123456@localhost:5672?connection_attempts=5&retry_delay=5'

API_URL_360=https://waba-sandbox.360dialog.io

# usado para mosrar opções não disponíveis normalmente.
ADMIN_DOMAIN=izing.io

# Dados para utilização do canal do facebook
FACEBOOK_APP_ID=3237415623048660
FACEBOOK_APP_SECRET_KEY=3266214132b8c98ac59f3e957a5efeaaa13500

# Forçar utilizar versão definida via cache (https://wppconnect.io/pt-BR/whatsapp-versions/)
WEB_VERSION

# Customizar opções do pool de conexões DB
POSTGRES_POOL_MAX
POSTGRES_POOL_MIN
POSTGRES_POOL_ACQUIRE
POSTGRES_POOL_IDLE
EOF

# Ajuste de dependências
sed -i -e 's|"whatsapp-web.js": "github:ldurans/whatsapp-web.js#webpack-exodus"|"whatsapp-web.js": "^1.23.0"|' package.json | tee -a $LOGFILE

# Instalação e construção do backend
npm install | tee -a $LOGFILE
npm run build | tee -a $LOGFILE
npx sequelize db:migrate | tee -a $LOGFILE
npx sequelize db:seed:all | tee -a $LOGFILE

# Preparação do frontend
cd ../frontend
pwd | tee -a $LOGFILE
rm -rf .env.example
echo "VUE_URL_API='https://$FRONTEND_URL'" > .env
echo "VUE_FACEBOOK_APP_ID='23156312477653241'" >> .env

# Instalação e construção do frontend
# Alteração do nvm para versao 16 para a instalacao do front end
nvm use 16

npm i -g @quasar/cli | tee -a $LOGFILE
npm install | tee -a $LOGFILE
quasar build -P -m pwa | tee -a $LOGFILE
pwd | tee -a $LOGFILE
cd dist/
pwd | tee -a $LOGFILE
cp -rf pwa pwa.bkp

# Preparação do PM2

source ~/.bashrc
pm2 startup ubuntu -u root | tee -a $LOGFILE
pm2 start /home/infoway/izing.io/backend/dist/server.js --name "izing-backend" | tee -a $LOGFILE


# Configuração do Nginx
touch /etc/nginx/sites-available/$BACKEND_URL
ln -s /etc/nginx/sites-available/$BACKEND_URL /etc/nginx/sites-enabled/
cat <<EOF >/etc/nginx/sites-available/$BACKEND_URL
server {
    listen 80;
    server_name $BACKEND_URL;
    return 301 https://\$server_name\$request_uri; # Redireciona HTTP para HTTPS
}

server {
    listen 443 ssl;
    server_name $BACKEND_URL;

    ssl_certificate /etc/ssl/certs/$BACKEND_URL.crt;
    ssl_certificate_key /etc/ssl/private/$BACKEND_URL.key;

    client_max_body_size 500M;

    location / {
        proxy_pass http://localhost:8081; # Ajuste a porta conforme necessário
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF


# Configuração do Nginx
touch /etc/nginx/sites-available/$FRONTEND_URL
ln -s /etc/nginx/sites-available/$FRONTEND_URL /etc/nginx/sites-enabled/
cat <<EOF >/etc/nginx/sites-available/$FRONTEND_URL
server {
    listen 80;
    server_name $FRONTEND_URL;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $FRONTEND_URL;

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

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -config $CONFIG_FILE
rm $CONFIG_FILE


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
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -config $CONFIG_FILE

# Excluindo o arquivo de configuração
rm $CONFIG_FILE




echo "Configuração concluída. Por favor, configure manualmente os arquivos de configuração do Nginx."

reboot
