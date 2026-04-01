#!/bin/bash
set -e

escape_sed_replacement() {
    # Escape characters that are special in sed replacement when using '|' as the delimiter.
    # This ensures secrets containing '&' or '|' do not break the substitution.
    printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

# copy template config to writable location if it doesn't exist or is a template
cp /data/homeserver.yaml.template /data/homeserver.yaml

# replace password placeholder in config
if [ -n "$POSTGRES_PASSWORD" ]; then
    escaped_POSTGRES_PASSWORD=$(escape_sed_replacement "$POSTGRES_PASSWORD")
    sed -i "s|password: \"POSTGRES_PASSWORD_PLACEHOLDER\"|password: \"$escaped_POSTGRES_PASSWORD\"|" /data/homeserver.yaml
fi

# replace OIDC client secret placeholder
if [ -n "$SYNAPSE_OIDC_CLIENT_SECRET" ]; then
    escaped_SYNapse_OIDC_CLIENT_SECRET=$(escape_sed_replacement "$SYNAPSE_OIDC_CLIENT_SECRET")
    sed -i "s|client_secret: \"OIDC_SECRET_PLACEHOLDER\"|client_secret: \"$escaped_SYNapse_OIDC_CLIENT_SECRET\"|" /data/homeserver.yaml
fi

# replace S3 credentials placeholders
if [ -n "$S3_ACCESS_KEY" ]; then
    escaped_S3_ACCESS_KEY=$(escape_sed_replacement "$S3_ACCESS_KEY")
    sed -i "s|access_key_id: \"S3_ACCESS_KEY_PLACEHOLDER\"|access_key_id: \"$escaped_S3_ACCESS_KEY\"|" /data/homeserver.yaml
fi
if [ -n "$S3_SECRET_KEY" ]; then
    escaped_S3_SECRET_KEY=$(escape_sed_replacement "$S3_SECRET_KEY")
    sed -i "s|secret_access_key: \"S3_SECRET_KEY_PLACEHOLDER\"|secret_access_key: \"$escaped_S3_SECRET_KEY\"|" /data/homeserver.yaml
fi
if [ -n "$S3_ENDPOINT" ]; then
    escaped_S3_ENDPOINT=$(escape_sed_replacement "$S3_ENDPOINT")
    sed -i "s|endpoint_url: \"S3_ENDPOINT_PLACEHOLDER\"|endpoint_url: \"$escaped_S3_ENDPOINT\"|" /data/homeserver.yaml
fi
if [ -n "$S3_REGION" ]; then
    escaped_S3_REGION=$(escape_sed_replacement "$S3_REGION")
    sed -i "s|region_name: \"S3_REGION_PLACEHOLDER\"|region_name: \"$escaped_S3_REGION\"|" /data/homeserver.yaml
fi
if [ -n "$S3_MEDIA_BUCKET" ]; then
    escaped_S3_MEDIA_BUCKET=$(escape_sed_replacement "$S3_MEDIA_BUCKET")
    sed -i "s|bucket: \"S3_MEDIA_BUCKET_PLACEHOLDER\"|bucket: \"$escaped_S3_MEDIA_BUCKET\"|" /data/homeserver.yaml
fi

# replace SMTP password placeholder
if [ -n "$SMTP_PASSWORD" ]; then
    escaped_SMTP_PASSWORD=$(escape_sed_replacement "$SMTP_PASSWORD")
    sed -i "s|smtp_pass: \"SMTP_PASSWORD_PLACEHOLDER\"|smtp_pass: \"$escaped_SMTP_PASSWORD\"|" /data/homeserver.yaml
fi

# exec the original entrypoint
exec /start.py "$@"
