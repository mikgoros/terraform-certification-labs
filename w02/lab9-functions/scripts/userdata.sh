#!/bin/bash

set -euo pipefail

df update-y
dnf install -y nginx
systemctl enable nginx
echo  "<h1>Servido por Terraform</h1>" > /usr/share/nginx/html/index.html