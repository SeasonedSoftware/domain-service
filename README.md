# domain-service fn

This functions for (fnproject.io) receives a json via stdin with id of dns_hosted_zone and action then create a hosted_zone in aws (using route53).

## input format
```
{
  "id":"community_id",
  "domain":"domain.example.org",
  "action":"create_hosted_zone",
  "api_key": "jwt_token_hs512_with_jwt_secret"
}
```


## output format
```
{
  status: "200",
  response: "domain_name"
}
```


## how use

```
git clone https://github.com/nossas/domain-service.git
cd domain-service

fn apps config s YOUR_APP DATABASE_URL postgres://connection_string
fn apps config s YOUR_APP AWS_REGION aws_region
fn apps config s YOUR_APP AWS_ACCESS_KEY_ID aws_access_key_id
fn apps config s YOUR_APP AWS_SECRET_ACCESS_KEY aws_secret_access_key
fn apps config s YOUR_APP AWS_ROUTE_IP aws_route_ip
fn apps config s YOUR_APP JWT_SECRET jwt_secret_key

fn deploy --app YOUR_APP --local
```

calling the function via fn cli
```
echo JWT_TOKEN_WITH_JSON_STRUCT | fn call YOU_APP /domain-service
```


