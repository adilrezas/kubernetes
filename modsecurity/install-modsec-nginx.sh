#!/bin/bash
set -e

echo "🧰 Installing dependencies..."
apt update
apt install -y \
  git build-essential autoconf automake libtool \
  libcurl4-openssl-dev liblua5.3-dev libfuzzy-dev ssdeep \
  libxml2 libxml2-dev libpcre2-dev zlib1g-dev libyajl-dev \
  pkg-config doxygen libgeoip-dev wget libpcre3 libpcre3-dev \
  libssl-dev

cd /usr/local/src

echo "📥 Cloning ModSecurity v3..."
git clone --depth 1 -b v3/master https://github.com/SpiderLabs/ModSecurity
cd ModSecurity
git submodule init
git submodule update
./build.sh
./configure
make -j"$(nproc)"
make install

echo "📥 Cloning ModSecurity-nginx connector..."
cd /usr/local/src
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

echo "📥 Downloading NGINX source to match installed version..."
NGINX_VERSION=$(nginx -v 2>&1 | grep -o '[0-9.]*')
wget http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz
tar -zxvf nginx-$NGINX_VERSION.tar.gz
cd nginx-$NGINX_VERSION

echo "⚙️ Building NGINX ModSecurity dynamic module..."
./configure --with-compat --add-dynamic-module=../ModSecurity-nginx
make modules
mkdir -p /etc/nginx/modules
cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/

echo "🔧 Updating nginx.conf to load module..."
if ! grep -q 'load_module /etc/nginx/modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf; then
  sed -i '1iload_module /etc/nginx/modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf
fi

echo "📁 Creating ModSecurity config directory..."
mkdir -p /etc/nginx/modsec
cd /etc/nginx/modsec

echo "📥 Downloading ModSecurity base config..."
wget https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended
cp modsecurity.conf-recommended main.conf
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' main.conf

echo "📥 Downloading unicode.mapping..."
wget https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping

echo "📥 Cloning OWASP Core Rule Set..."
git clone --depth 1 https://github.com/coreruleset/coreruleset
cp coreruleset/crs-setup.conf.example coreruleset/crs-setup.conf

echo "📎 Including CRS in main.conf..."
echo -e '\n# OWASP CRS\nInclude /etc/nginx/modsec/coreruleset/crs-setup.conf\nInclude /etc/nginx/modsec/coreruleset/rules/*.conf' >> main.conf

echo "⚙️ Enabling ModSecurity in default server block..."
SITE_CONF="/etc/nginx/sites-available/default"
if ! grep -q 'modsecurity on;' "$SITE_CONF"; then
  sed -i '/server_name _;/a \\tmodsecurity on;\n\tmodsecurity_rules_file /etc/nginx/modsec/main.conf;' "$SITE_CONF"
fi

echo "🔍 Testing nginx config..."
nginx -t

echo "🚀 Restarting NGINX..."
systemctl restart nginx

echo "✅ ModSecurity with OWASP CRS is now active!"
