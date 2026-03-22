#!/bin/bash
set -e

# Write shared secret for region authentication
if [ -n "$MAAS_SECRET" ]; then
    mkdir -p /var/lib/maas
    echo -n "$MAAS_SECRET" > /var/lib/maas/secret
    chmod 640 /var/lib/maas/secret
fi

# Register with region controller
maas-rack config \
    --maas-url "${MAAS_URL:-http://maas-region-svc:5240/MAAS}" \
    --secret "${MAAS_SECRET}"

# Start rack daemon
exec maas-rackd