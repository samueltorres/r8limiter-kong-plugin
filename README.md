# r8limiter-kong-plugin

```bash
curl -X GET \
  http://localhost:8000 \
  -H 'Accept: */*' \
  -H 'Accept-Encoding: gzip, deflate' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjbGllbnRfdWlkIjoiMTIzNCIsImNsaWVudF90ZW5hbnRJZCI6IjEyMzQ1In0._2Z3HBY_zSPPvFeWYmH56FaMLntMA8aqz4qnISF033s' \
  -H 'Cache-Control: no-cache' \
  -H 'Connection: keep-alive' \
  -H 'Host: localhost:8000' \
  -H 'Postman-Token: 96774821-63c5-46fe-9236-b0c0990428a7,c6f0d6f8-ae37-411d-93f6-4d50a43f8d39' \
  -H 'User-Agent: PostmanRuntime/7.19.0' \
  -H 'cache-control: no-cache' \
  -H 'ff-country: PT'
```

```yaml
domains:
  - domain: kong
    rules:
      - name: authenticated users
        labels:
          - key: authenticated
            value: "true"
          - key: user_id
        limit:
          unit: hour
          requests: 60

      - name: any user
        labels:
          - key: user_id
        limit:
          unit: hour
          requests: 1000

      - name: ip address
        labels:
          - key: ip_address
        limit:
          unit: minute
          requests: 500
```