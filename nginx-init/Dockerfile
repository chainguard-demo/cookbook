FROM nginx:1.25

# Copy your custom nginx.conf into a temp path
COPY nginx.conf /custom/nginx.conf
COPY mime.types /custom/mime.types

# Copy and prepare config at container startup using entrypoint
CMD cp /custom/nginx.conf /etc/nginx/nginx.conf && \
    cp /custom/mime.types /etc/nginx/mime.types && \
    chmod 644 /etc/nginx/* && \
    /docker-entrypoint.sh true