#!/usr/bin/env bash

echo "Backing up existing letsencrypt certificate..."
today=$(date +"%Y-%m-%d")
mv /etc/letsencrypt/letsencrypt.crt /etc/letsencrypt/letsencrypt.crt.${today} || true
echo ""

echo "Opening port 80/tcp..."
ufw allow 80/tcp
echo ""

echo "Starting nginx container..."
docker run -d --name "letsencrypt-nginx" -p "80:80" -v "/etc/nginx-docker/letsencrypt.conf:/etc/nginx/nginx.conf:ro" "/var/www/challenges/:/var/www/challenges/" nginx:latest
echo ""

echo "Running acme_tiny..."
/bin/su -c "python3 /usr/local/bin/acme_tiny.py --account-key /etc/letsencrypt/account.key --csr /etc/letsencrypt/letsencrypt.csr --acme-dir /var/www/challenges/ > /etc/letsencrypt/letsencrypt.crt" -- letsencrypt
echo ""

echo "Stopping and removing nginx container..."
docker stop letsencrypt-nginx
docker rm letsencrypt-nginx
echo ""

echo "Closing port 80/tcp..."
ufw delete allow 80/tcp
echo ""