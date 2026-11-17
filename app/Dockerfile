# Small static web page served by nginx running as a non-root user on port 8080.
FROM nginxinc/nginx-unprivileged:stable-alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080
