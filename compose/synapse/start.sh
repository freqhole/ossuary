#!/bin/bash
set -e

# copy template config to writable location if it doesn't exist or is a template
cp /data/homeserver.yaml.template /data/homeserver.yaml

# replace password placeholder in config
if [ -n "$POSTGRES_PASSWORD" ]; then
    sed -i "s/password: \"POSTGRES_PASSWORD_PLACEHOLDER\"/password: \"$POSTGRES_PASSWORD\"/" /data/homeserver.yaml
fi

# replace OIDC client secret placeholder
if [ -n "$SYNAPSE_OIDC_CLIENT_SECRET" ]; then
    sed -i "s/client_secret: \"OIDC_SECRET_PLACEHOLDER\"/client_secret: \"$SYNAPSE_OIDC_CLIENT_SECRET\"/" /data/homeserver.yaml
fi

# replace S3 credentials placeholders
if [ -n "$S3_ACCESS_KEY" ]; then
    sed -i "s/access_key_id: \"S3_ACCESS_KEY_PLACEHOLDER\"/access_key_id: \"$S3_ACCESS_KEY\"/" /data/homeserver.yaml
fi
if [ -n "$S3_SECRET_KEY" ]; then
    sed -i "s/secret_access_key: \"S3_SECRET_KEY_PLACEHOLDER\"/secret_access_key: \"$S3_SECRET_KEY\"/" /data/homeserver.yaml
fi
if [ -n "$S3_ENDPOINT" ]; then
    sed -i "s|endpoint_url: \"S3_ENDPOINT_PLACEHOLDER\"|endpoint_url: \"$S3_ENDPOINT\"|" /data/homeserver.yaml
fi
if [ -n "$S3_REGION" ]; then
    sed -i "s/region_name: \"S3_REGION_PLACEHOLDER\"/region_name: \"$S3_REGION\"/" /data/homeserver.yaml
fi
if [ -n "$S3_MEDIA_BUCKET" ]; then
    sed -i "s/bucket: \"S3_MEDIA_BUCKET_PLACEHOLDER\"/bucket: \"$S3_MEDIA_BUCKET\"/" /data/homeserver.yaml
fi

# replace SMTP password placeholder
if [ -n "$SMTP_PASSWORD" ]; then
    sed -i "s/smtp_pass: \"SMTP_PASSWORD_PLACEHOLDER\"/smtp_pass: \"$SMTP_PASSWORD\"/" /data/homeserver.yaml
fi

# exec the original entrypoint
exec /start.py "$@"
