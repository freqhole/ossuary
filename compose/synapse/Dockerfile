FROM ghcr.io/element-hq/synapse:latest

# install S3 storage provider for OVH object storage
RUN pip install --no-cache-dir synapse-s3-storage-provider

# custom entrypoint to inject secrets
COPY start.sh /start.sh
RUN chmod +x /start.sh
ENTRYPOINT ["/start.sh"]
