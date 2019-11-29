# r8limiter-kong-plugin

version: '3'

services:
  kong:
    image: kong
    network_mode: host
    ports:
      - "8000:8000/tcp"
      - "8001:8001/tcp"
      - "8443:8443/tcp"
      - "8444:8444/tcp"
    volumes:
      - ./kong:/usr/local/custom/kong
      - ./config:/tmp/config
    environment:
      - KONG_PLUGINS=r8limiter
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/config/kong.yml
      - KONG_LUA_PACKAGE_PATH=/usr/local/custom/?.lua;;
    command: "sleep 100000"
