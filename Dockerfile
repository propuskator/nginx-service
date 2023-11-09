FROM nginx:stable-alpine

RUN apk update && apk add tzdata bash
RUN curl -sSL https://git.io/get-mo -o mo
RUN chmod +x mo
RUN mv mo /usr/local/bin/
RUN rm /etc/nginx/conf.d/default.conf

COPY etc/nginx.conf /etc/nginx/nginx.conf
COPY etc/robots.txt /etc/nginx/robots.txt
COPY bin bin
COPY templates templates

ENTRYPOINT [ "/bin/init.sh" ]
CMD [ "nginx", "-g", "\"daemon off;\"" ]