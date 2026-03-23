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
mkdir -p /var/lib/maas/temporal
if [ -n "$MAAS_SECRET" ]; then
    echo -n "$MAAS_SECRET" > /var/lib/maas/secret
    chmod 640 /var/lib/maas/secret
fi

# maas ユーザーが書き込めるよう所有者を変更
chown -R maas:maas /var/lib/maas
chown root:maas /etc/maas/regiond.conf
chmod 640 /etc/maas/regiond.conf

# Run Django database migrations
maas-region dbupgrade

# Hand off to systemd (manages all MAAS services)
exec /sbin/init