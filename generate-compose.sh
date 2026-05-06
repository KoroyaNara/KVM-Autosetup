#!/usr/bin/env bash
# ============================================================
#  KVM AutoSetup — Docker Compose Template Generator
#  Dipanggil oleh kvm-autosetup.sh, atau standalone:
#  bash generate-compose.sh <role> <tech> <vm_name>
# ============================================================

COMPOSE_OUT_DIR="${COMPOSE_OUT_DIR:-./compose-templates}"
mkdir -p "$COMPOSE_OUT_DIR"

gen_fe_react() {
  local name="$1"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<'EOF'
version: "3.9"
services:
  frontend:
    image: node:20-alpine
    container_name: frontend-app
    working_dir: /app
    volumes:
      - ./app:/app
    ports:
      - "3000:3000"
    command: sh -c "npm install && npm run dev -- --host 0.0.0.0"
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: frontend-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - frontend
    restart: unless-stopped
EOF
}

gen_be_node() {
  local name="$1"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<'EOF'
version: "3.9"
services:
  backend:
    image: node:20-alpine
    container_name: backend-app
    working_dir: /app
    volumes:
      - ./app:/app
    ports:
      - "4000:4000"
    environment:
      - NODE_ENV=production
      - PORT=4000
    command: sh -c "npm install && npm run start"
    restart: unless-stopped
EOF
}

gen_be_laravel() {
  local name="$1"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<'EOF'
version: "3.9"
services:
  php:
    image: php:8.2-fpm-alpine
    container_name: laravel-app
    working_dir: /var/www/html
    volumes:
      - ./app:/var/www/html
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: laravel-nginx
    ports:
      - "80:80"
    volumes:
      - ./app:/var/www/html
      - ./nginx/laravel.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - php
    restart: unless-stopped
EOF
}

gen_db_mysql() {
  local name="$1" pass="${2:-Admin1234!}"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<EOF
version: "3.9"
services:
  mysql:
    image: mysql:8.0
    container_name: mysql-db
    environment:
      MYSQL_ROOT_PASSWORD: ${pass}
      MYSQL_DATABASE: appdb
      MYSQL_USER: appuser
      MYSQL_PASSWORD: ${pass}
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      - ./init:/docker-entrypoint-initdb.d
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  mysql_data:
EOF
}

gen_db_postgres() {
  local name="$1" pass="${2:-Admin1234!}"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<EOF
version: "3.9"
services:
  postgres:
    image: postgres:16-alpine
    container_name: postgres-db
    environment:
      POSTGRES_PASSWORD: ${pass}
      POSTGRES_USER: appuser
      POSTGRES_DB: appdb
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pg_data:
EOF
}

gen_db_mongo() {
  local name="$1" pass="${2:-Admin1234!}"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<EOF
version: "3.9"
services:
  mongodb:
    image: mongo:7.0
    container_name: mongo-db
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${pass}
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    restart: unless-stopped

  mongo-express:
    image: mongo-express
    container_name: mongo-ui
    ports:
      - "8081:8081"
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: admin
      ME_CONFIG_MONGODB_ADMINPASSWORD: ${pass}
      ME_CONFIG_MONGODB_URL: mongodb://admin:${pass}@mongodb:27017/
    depends_on:
      - mongodb
    restart: unless-stopped

volumes:
  mongo_data:
EOF
}

gen_monitoring_wazuh() {
  local name="$1"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<'EOF'
version: "3.9"

# Wazuh single-node Docker deployment
# Ref: https://documentation.wazuh.com/current/deployment-options/docker/

services:
  wazuh.manager:
    image: wazuh/wazuh-manager:4.7.2
    container_name: wazuh-manager
    hostname: wazuh.manager
    restart: unless-stopped
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 655360
        hard: 655360
    ports:
      - "1514:1514"
      - "1515:1515"
      - "514:514/udp"
      - "55000:55000"
    environment:
      - INDEXER_URL=https://wazuh.indexer:9200
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=SecretPassword
      - FILEBEAT_SSL_VERIFICATION_MODE=full
      - SSL_CERTIFICATE_AUTHORITIES=/etc/ssl/root-ca.pem
      - SSL_CERTIFICATE=/etc/ssl/filebeat.pem
      - SSL_KEY=/etc/ssl/filebeat.key
      - API_USERNAME=wazuh-wui
      - API_PASSWORD=MyS3cr37P450r.*-
    volumes:
      - wazuh_api_configuration:/var/ossec/api/configuration
      - wazuh_etc:/var/ossec/etc
      - wazuh_logs:/var/ossec/logs
      - wazuh_queue:/var/ossec/queue
      - wazuh_var_multigroups:/var/ossec/var/multigroups
      - wazuh_integrations:/var/ossec/integrations
      - wazuh_active_response:/var/ossec/active-response/bin
      - wazuh_agentless:/var/ossec/agentless
      - wazuh_wodles:/var/ossec/wodles
      - filebeat_etc:/etc/filebeat
      - filebeat_var:/var/lib/filebeat

  wazuh.indexer:
    image: wazuh/wazuh-indexer:4.7.2
    container_name: wazuh-indexer
    hostname: wazuh.indexer
    restart: unless-stopped
    ports:
      - "9200:9200"
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"

  wazuh.dashboard:
    image: wazuh/wazuh-dashboard:4.7.2
    container_name: wazuh-dashboard
    hostname: wazuh.dashboard
    restart: unless-stopped
    ports:
      - "443:5601"
    environment:
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=SecretPassword
      - WAZUH_API_URL=https://wazuh.manager
      - DASHBOARD_USERNAME=kibanaserver
      - DASHBOARD_PASSWORD=kibanaserver
      - API_USERNAME=wazuh-wui
      - API_PASSWORD=MyS3cr37P450r.*-
    depends_on:
      - wazuh.indexer
      - wazuh.manager

volumes:
  wazuh_api_configuration:
  wazuh_etc:
  wazuh_logs:
  wazuh_queue:
  wazuh_var_multigroups:
  wazuh_integrations:
  wazuh_active_response:
  wazuh_agentless:
  wazuh_wodles:
  filebeat_etc:
  filebeat_var:
EOF
}

gen_monitoring_grafana() {
  local name="$1"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<'EOF'
version: "3.9"
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - prometheus
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
EOF
}

gen_lb_nginx() {
  local name="$1"
  cat > "$COMPOSE_OUT_DIR/${name}-compose.yml" <<'EOF'
version: "3.9"
services:
  nginx-lb:
    image: nginx:alpine
    container_name: nginx-loadbalancer
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/nginx/ssl:ro
      - nginx_logs:/var/log/nginx
    restart: unless-stopped

volumes:
  nginx_logs:
EOF

  # Also generate sample nginx.conf
  mkdir -p "$COMPOSE_OUT_DIR/nginx/conf.d"
  cat > "$COMPOSE_OUT_DIR/nginx/nginx.conf" <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;
    gzip on;

    upstream frontend_pool {
        least_conn;
        server 192.168.122.10:3000;  # FE VM IP
    }

    upstream backend_pool {
        least_conn;
        server 192.168.122.11:4000;  # BE VM IP
    }

    include /etc/nginx/conf.d/*.conf;
}
EOF
}

# ── CLI entrypoint ────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ROLE="${1:-}"; TECH="${2:-}"; NAME="${3:-vm}"
  case "$ROLE" in
    fe)      gen_fe_react "$NAME" ;;
    be)
      case "$TECH" in
        *Laravel*) gen_be_laravel "$NAME" ;;
        *)         gen_be_node "$NAME" ;;
      esac
      ;;
    db)
      case "$TECH" in
        *MySQL*)    gen_db_mysql "$NAME" "$4" ;;
        *Postgres*) gen_db_postgres "$NAME" "$4" ;;
        *Mongo*)    gen_db_mongo "$NAME" "$4" ;;
      esac
      ;;
    monitoring)
      case "$TECH" in
        *Wazuh*)   gen_monitoring_wazuh "$NAME" ;;
        *Grafana*) gen_monitoring_grafana "$NAME" ;;
      esac
      ;;
    lb) gen_lb_nginx "$NAME" ;;
    *) echo "Usage: $0 <role> <tech> <vm_name> [db_pass]"; exit 1 ;;
  esac
  echo "Docker Compose template: $COMPOSE_OUT_DIR/${NAME}-compose.yml"
fi
