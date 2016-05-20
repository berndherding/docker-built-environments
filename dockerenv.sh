#!/bin/bash

# include some helper function used in both training and production environment
. helpers.include

ENVIRONMENT=local

OUT=${1:-/dev/null}

if [ "$ENVIRONMEN" = "aws" ] ; then
  REGION=${2:-eu-central-1}
fi

check_preconditions



usage $ENVIRONMENT

cat << EOF
  PRECONDITIONS:

  - have sudo write access to /etc/hosts
  - have an AWS account

  if you can meet all preconditions, press RETURN
EOF

read



# make sure there is a proper aws configuration

echo '*** please make sure all these values are set. if they are, just confirm them:'

aws configure

vpcid=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)



download_static_zip



# build a custom nginx image. the nginx will serve static content 
# from "/static" (see nginx/Dockerfile) and otherwise proxy_pass to a
# jetty appication server (see below)

echo "*** build and push custom nginx image to myregistry"

docker build --no-cache -t myregistry:5000/mynginx:latest nginx &> $OUT
docker push myregistry:5000/mynginx:latest &> $OUT



download_application_war



# build custom jetty image with application from .war as ROOT application

echo "*** build and push custom jetty image to myregistry"

docker build --no-cache -t myregistry:5000/myjetty:latest jetty &> $OUT
docker push myregistry:5000/myjetty:latest &> $OUT



# create new dockerenv stack using cloud formation

echo "*** create dockerenv stack on AWS $REGION using cloudformation"

./add_user_data.sh $REGISTRY_IP dockerenv.yaml dockerenv.tmpl > dockerenv.json

aws cloudformation create-stack \
  --region $REGION \
  --stack-name dockerenv \
  --template-body file://dockerenv.json \
  --parameters ParameterKey=myVpcId,ParameterValue=$vpcid &> $OUT

echo "*** please wait for stack to complete. this may take a few minutes."
aws cloudformation wait stack-create-complete --stack-name dockerenv --output text --no-paginate &> $OUT

LOAD_BALANCER_NAME=$(aws cloudformation describe-stack-resources --stack-name dockerenv --query 'StackResources[?ResourceType==`AWS::ElasticLoadBalancing::LoadBalancer`]'.PhysicalResourceId --output text)

HOSTED_ZONE_NAME=$(aws elb describe-load-balancers --load-balancer-names $LOAD_BALANCER_NAME --query 'LoadBalancerDescriptions[0].CanonicalHostedZoneName' --output text)

cat << EOF
*** stack complete. you can now check

  http://$HOSTED_ZONE_NAME

in your browser.

NOTE
before you call the script again, make sure to detroy the
dockerenv cloudformation stack via AWS console.

if you destroy the myregistry as well, make sure to clean up
the corresponding security groups, too.
EOF
