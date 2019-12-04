FROM kong:alpine
COPY ./kong /usr/local/custom/kong
ENV KONG_LUA_PACKAGE_PATH=/usr/local/custom/?.lua;;
CMD ["kong", "docker-start"]