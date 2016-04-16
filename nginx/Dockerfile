FROM nginx:latest

RUN rm /etc/nginx/conf.d/default.conf

COPY default.conf /etc/nginx/conf.d/default.conf
COPY static /usr/share/nginx/static/

# RUN cat /etc/nginx/conf.d/default.conf
