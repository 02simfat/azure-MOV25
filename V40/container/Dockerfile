# Dockerfile - receptet for imagen novatrix-web (V40)
# Bygger Novatrix kundtjanstsida som en container med webbservern nginx.
# Byggs av GitHub Actions (.github/workflows/v40-bygg-image.yml) till
# ghcr.io/02simfat/novatrix-web:v1

# 1. Basimage: en liten Linux (Alpine) dar nginx redan ar installerad.
FROM nginx:alpine

# 2. Kopiera in var webbsida dit nginx letar efter filer att visa.
COPY index.html /usr/share/nginx/html/index.html

# 3. Containern lyssnar pa port 80 (vanlig webbtrafik, HTTP).
EXPOSE 80

# Ingen CMD behovs: basimagen startar redan nginx nar containern startar.
