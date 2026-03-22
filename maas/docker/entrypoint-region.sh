#!/bin/bash
set -e

# Write regiond configuration from environment variables
mkdir -p /etc/maas
cat > /etc/maas/regiond.conf <<EOF
database_host: ${MAAS_POSTGRES_HOST:-maas-postgres-svc}
database_port: 5432
database_name: ${MAAS_POSTGRES_DB:-maas}
database_user: ${MAAS_POSTGRES_USER}
database_pass: ${MAAS_POSTGRES_PASS}
maas_url: ${MAAS_URL:-http://localhost:5240/MAAS}
EOF

# Write shared secret for rack controller authentication
if [ -n "$MAAS_SECRET" ]; then
    mkdir -p /var/lib/maas
    echo -n "$MAAS_SECRET" > /var/lib/maas/secret
    chmod 640 /var/lib/maas/secret
fi

# Create temporal directory required by temporal-server
mkdir -p /var/lib/maas/temporal

# Run Django database migrations
maas-region dbupgrade

# Start Temporal server (background)
/usr/sbin/temporal-server \
    -e production \
    -r "/var/lib/maas/temporal/" \
    -c "" \
    --allow-no-auth start &

# Wait for Temporal to be ready
sleep 5

# Start MAAS API server (background)
/usr/sbin/maas-apiserver &

# Start Temporal worker (background)
/usr/sbin/maas-temporal-worker &

# Start region daemon (foreground)
exec /usr/sbin/regiond