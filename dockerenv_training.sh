#!/bin/bash

# include some helper function used in both training and production environment
. helpers.include

OUT=${1:-/dev/null}

check_preconditions



usage training

cat << EOF
  PRECONDITIONS:

  - have the root password for write access to /etc/hosts

  if you can meet all preconditions, press RETURN
EOF

read



# check if myregistry is running and get its IP

docker-machine ls | grep "^myregistry" &> /dev/null
HAS_REGISTRY=$?

# if not, create a new registry

if [ $HAS_REGISTRY -ne 0 ] ; then

  echo '*** create new VM ”myregistry”'
  
  docker-machine create --driver virtualbox myregistry &> $OUT
fi
  
REGISTRY_IP=$(docker-machine ip myregistry)
eval $(docker-machine env myregistry)

if [ $HAS_REGISTRY -eq 0 ] ; then
  echo "*** using existing \"myregistry\" VM with ip $REGISTRY_IP"
fi



# if we had to create a new myregistry VM, put it into /etc/hosts

grep "^$REGISTRY_IP *myregistry" /etc/hosts &> /dev/null
if [ $? -ne 0 ] ; then

  echo "*** put \"myregistry\" ip $REGISTRY_IP into /etc/hosts (backup in /tmp/hosts)"

  cp /etc/hosts /tmp
  put_entry_into_etc_hosts $REGISTRY_IP  myregistry
fi




# start new registry on myregistry:5000 in a docker container

if [ $HAS_REGISTRY -ne 0 ] ; then

  echo '*** docker run private registry on new VM "myregistry"'

  docker run -d -p 5000:5000 --restart=always --name myregistry registry:2 &> $OUT
fi



download_static_zip



# build a custom nginx image. the nginx will serve static content 
# from "/static" (see nginx/Dockerfile) and otherwise proxy_pass to a
# jetty appication server (see below)

echo "*** build and push custom nginx image to myregistry"

docker build --no-cache -t myregistry:5000/mynginx:latest nginx &> $OUT
docker push myregistry:5000/mynginx:latest &> $OUT



download_dockerenv_war



# build custom jetty image with dockerenv as ROOT application

echo "*** build and push custom jetty image to myregistry"

docker build --no-cache -t myregistry:5000/myjetty:latest jetty &> $OUT
docker push myregistry:5000/myjetty:latest &> $OUT



echo "*** check and destroy old dockerenv remains"
docker-machine stop  dockerenv &> /dev/null
docker-machine rm -f dockerenv &> /dev/null



# create a new VM "dockerenv"
# --virtualbox-no-share prevents docker from sharing your host's /Users directory.
#   the /Users directory seems to be needed by prevayler, but we don't want the app
#   messing around with it, so better create a new one in dockerenv.yaml.
# --engine-insecure-registry tells the docker daemon that pull requests to myregistry
#   shall be done using http. in real life, https should be used, but this would need
#   a cert structure

echo '*** create new VM "dockerenv"'

docker-machine create --driver virtualbox --virtualbox-no-share --engine-insecure-registry myregistry:5000 dockerenv &> $OUT
docker-machine ssh dockerenv "sudo sh -c 'echo \""$REGISTRY_IP" myregistry\" >> /etc/hosts'"

eval $(docker-machine env dockerenv)
STACK_IP=$(docker-machine ip dockerenv)



echo "*** put \"dockerenv\" ip $STACK_IP into /etc/hosts"
  
put_entry_into_etc_hosts $STACK_IP dockerenv


  
# now create a whole stack setup with docker-compose, according to
# definitions in a compose yaml file. the stack will be running on
# the "dockerenv" VM.

echo "*** create dockerenv stack on local dockerenv VW"

docker-compose -f dockerenv.yaml up -d &> $OUT

cat << EOF
*** stack complete. however, application may take longer. check

  http://dockerenv

in your browser in a few moments.

NOTE
before you call the script again, make sure to destroy the
dockerenv VM via docker-machine. you may want to do the
same for the myregistry VM.
EOF
