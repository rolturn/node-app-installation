#!/bin/bash
#
# Author: "Roland Turner" <rol.turn@gmail.com>
# GitHub: https://github.com/rolturn
#
# The MIT License (MIT)
#
# Copyright (c) 2016 rolturn
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# This script is designed to automate the generation of files necessary to
# deploy new project

# PROJECT_NAME="$1"

SOURCE_PATH="`dirname \"$0\"`"              # relative
SOURCE_PATH="`( cd \"$SOURCE_PATH\" && pwd )`"  # absolutized and normalized
if [ -z "$SOURCE_PATH" ] ; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1  # fail
fi

BASE_REPO_PATH="/var/repos"
BASE_DEPLOY_PATH="/var/www"

for URL in "$@"
  do
  # remove everything after the last .
  # PROJECT_NAME=$(echo -e $URL | sed -e "s/\.[^\.]*$//")
  PROJECT_NAME=$(echo -e $URL | sed -e "s/\./_/g")
  # GIT Post Receive Source
  POST_RECEIVE_FILE_SOURCE="$(echo -e ${SOURCE_PATH})/configs/default_post-receive"
  # Supervisord Config File Source
  # \n/supervisor/conf.d/*
  # SUPERVISOR_CONFIG_FILE_SOURCE="$(echo -e ${SOURCE_PATH})/app_supervisor.conf"
  # Create Supervisor Config File
  # \n/supervisor/conf.d/*
  SUPERVISOR_CONFIG_DIRECTORY="/etc/supervisor/conf.d"
  mkdir -p $SUPERVISOR_CONFIG_DIRECTORY
  SUPERVISOR_PROJECT_CONFIG="$(echo -e ${SUPERVISOR_CONFIG_DIRECTORY})/$(echo -e ${PROJECT_NAME})_app.conf"
  rm $SUPERVISOR_PROJECT_CONFIG
  touch $SUPERVISOR_PROJECT_CONFIG
  printf "Created Supervisor Config: '$(echo -e ${SUPERVISOR_PROJECT_CONFIG})'\n\n"

  # Supervisor Log file Used to track PORT Numbers
  SUPERVISOR_LOG_FILE="$(echo -e ${SOURCE_PATH})/node_app_list.csv"
  if [ -f $SUPERVISOR_LOG_FILE ];
    then
      # this is critical as it establishes 4000 as the initial starting ping for port numbers
      sed '1s/^.*$/Project Name,Application Name,4000/' $SUPERVISOR_LOG_FILE > $SUPERVISOR_LOG_FILE.tmp && mv $SUPERVISOR_LOG_FILE.tmp $SUPERVISOR_LOG_FILE
    else
      tee $SUPERVISOR_LOG_FILE <<< "Project Name,Application Name,4000"
  fi
  # checkes if project already exists and if so remove it so that when recreated we know which PORTS are really being used
  awk "!/$(echo -e ${PROJECT_NAME}),/" $SUPERVISOR_LOG_FILE > $SUPERVISOR_LOG_FILE.tmp && mv $SUPERVISOR_LOG_FILE.tmp $SUPERVISOR_LOG_FILE

  # Nginx Config File Source
  NGINX_PROD_CONFIG_FILE_SOURCE="$(echo -e ${SOURCE_PATH})/configs/app_nginx_prod_server.conf"
  NGINX_NOT_PROD_CONFIG_FILE_SOURCE="$(echo -e ${SOURCE_PATH})/configs/app_nginx_not_prod_server.conf"
  # Create Nginx Config File
  # \n/nginx/conf.d/*
  NGINX_CONFIG_DIRECTORY="/etc/nginx/conf.d"
  mkdir -p $NGINX_CONFIG_DIRECTORY
  NGINX_PROJECT_CONFIG="$(echo -e ${NGINX_CONFIG_DIRECTORY})/$(echo -e ${PROJECT_NAME})_servers.conf"
  rm $NGINX_PROJECT_CONFIG
  touch $NGINX_PROJECT_CONFIG
  printf "Created Nginx Config: '$(echo -e ${NGINX_PROJECT_CONFIG})'\n\n"

  # function searches files and replaces elements
  # @parameters, $1=Search Element, $2=Replacement Element, $3=File
  function replaceElement {
  	sed -e "s|$1|$2|g" $3 > $3.tmp && mv $3.tmp $3
  	printf "'$(echo -e $1)': '$(echo -e $2)'\n$(echo -e $3)\n\n"
  }

  # function used to join an array
  # @parameters, $1=Separator Element, $d=Array
  function join {
  	local d=$1; shift; echo -e -n "$1"; shift; printf "%s" "${@/#/$d}";
  }

  # declare Environments needed
  declare -a ENVIRONMENTS=("production" "staging")

  ## now loop through the above array
  for ENVIRONMENT in "${ENVIRONMENTS[@]}"
  do

  	printf "\n##### CREATING ${ENVIRONMENT} ENVIRONMENT SPECIFICS FOR ${PROJECT_NAME}\n\n"

  	# identify and create git repo
  	REPO_ROOT="${BASE_REPO_PATH}/${PROJECT_NAME}/${ENVIRONMENT}/.git"
    if [ -d $REPO_ROOT ]
      then
        printf "Application Repo Location:\n$(echo -e ${REPO_ROOT})\n\n"
      else
        mkdir -p $REPO_ROOT
        printf "Created Application Repo Location:\n$(echo -e ${REPO_ROOT})\n\n"
    fi

  	# identify and create deployment directories
  	DEPLOY_ROOT=$(echo -e $REPO_ROOT | sed "s/repos/www/;s/\/.git$//g")
    if [ -d $DEPLOY_ROOT ]
      then
        printf "Application Deployment Location:\n$(echo -e ${DEPLOY_ROOT})\n\n"
      else
        mkdir -p $DEPLOY_ROOT
      	printf "Created Application Deployment Location:\n$(echo -e ${DEPLOY_ROOT})\n\n"
    fi

  	# Creating git repo
  	cd $REPO_ROOT
    if [ ! -f $(echo -e ${REPO_ROOT}/config) ]
      then
        git init --bare && printf "\n"
      else
        printf "GIT Repo Already Exists for $(echo -e ${ENVIRONMENT}).$(echo -e $URL)\n\n"
    fi
  	# Setting Environment Variables
  	POST_RECEIVE_FILE_ENV="$(echo -e ${REPO_ROOT})/hooks/post-receive"
  	APP_ENV_NAME="$(echo -e ${ENVIRONMENT})_$(echo -e ${PROJECT_NAME})"

  	# Copying post-receive file
  	cp $POST_RECEIVE_FILE_SOURCE $POST_RECEIVE_FILE_ENV
  	printf "Updated GIT post-receive:\n$(echo -e ${POST_RECEIVE_FILE_ENV})\n\n"
  	chmod +x $POST_RECEIVE_FILE_ENV
  	printf "Executable GIT post-receive:\n$(echo -e ${POST_RECEIVE_FILE_ENV})\n\n"

  	# Editing Post Receive file
  	printf "Editing post-receive file to be have specific needs of Environment \n\n"
  	# Replacing file elements needed to run post receive
  	replaceElement @AppName $PROJECT_NAME $POST_RECEIVE_FILE_ENV
  	replaceElement @Environment $ENVIRONMENT $POST_RECEIVE_FILE_ENV
  	replaceElement @AppEnvName $APP_ENV_NAME $POST_RECEIVE_FILE_ENV
    replaceElement @REPO_ROOT $REPO_ROOT $POST_RECEIVE_FILE_ENV
    replaceElement @DEPLOY_ROOT $DEPLOY_ROOT $POST_RECEIVE_FILE_ENV

  	# Adding NGINX configurations to NGINX config file
  	if [[ "$ENVIRONMENT" == "production" ]]
    	then
    		cat $NGINX_PROD_CONFIG_FILE_SOURCE >> $NGINX_PROJECT_CONFIG
    		# Defining how many Apps to build
    		TOTALPORTS=3
    	else
    		cat $NGINX_NOT_PROD_CONFIG_FILE_SOURCE >> $NGINX_PROJECT_CONFIG
    		# Defining how many Apps to build
    		TOTALPORTS=1
  	fi
  	printf "Added '$(echo -e ${ENVIRONMENT})' server configuration to $(echo -e ${NGINX_PROJECT_CONFIG})\n\n"

    #creating app logs
    LOG_DIRECTORY="$(echo -e ${DEPLOY_ROOT})/logs"
    mkdir -p $LOG_DIRECTORY
    ACCESS_LOG="$(echo -e ${LOG_DIRECTORY})/access.log"
    ERROR_LOG="$(echo -e ${LOG_DIRECTORY})/error.log"
    touch $ACCESS_LOG $ERROR_LOG

  	# Editing NGINX config file
  	replaceElement @AppName $PROJECT_NAME $NGINX_PROJECT_CONFIG
    replaceElement @URL $URL $NGINX_PROJECT_CONFIG
  	replaceElement @AppEnvName $APP_ENV_NAME $NGINX_PROJECT_CONFIG
  	replaceElement @Environment $ENVIRONMENT $NGINX_PROJECT_CONFIG
  	replaceElement @DeploymentRoot $DEPLOY_ROOT $NGINX_PROJECT_CONFIG
    replaceElement @AccessLog $ACCESS_LOG $NGINX_PROJECT_CONFIG
    replaceElement @ErrorLog $ERROR_LOG $NGINX_PROJECT_CONFIG

    # Fetching highest port from Supervisor Port Log
    # decided to fetch highest number so that there is no chance of overlap
  	# http://stackoverflow.com/questions/28790371/bash-finding-maximum-value-in-a-particular-csv-column
  	PORT_NUMBER=$(awk 'BEGIN { max=0 } $3 > max { max=$3; name=$3 } END { print name }' FS="," $SUPERVISOR_LOG_FILE)

  	# building Supervisor Configs
  	i="1"
  	while [ $i -le $TOTALPORTS ]
    	do
    		# Getting next available port #
    		PORT_NUMBER=$[$PORT_NUMBER+1]
    		# Creating App Name
    		APP_NAME="$(echo -e ${APP_ENV_NAME})_$(echo -e ${PORT_NUMBER})"
    		# Creating Array of App Names
    		APP_NAME_ARRAY[$i]=$APP_NAME
    		echo -e "[program:$(echo -e ${APP_NAME})]" >> $SUPERVISOR_PROJECT_CONFIG
        echo -e "command=/usr/local/bin/node $(echo -e ${DEPLOY_ROOT})/bin/www -p $(echo -e ${PORT_NUMBER})" >> $SUPERVISOR_PROJECT_CONFIG
        echo -e " " >> $SUPERVISOR_PROJECT_CONFIG

    		# Add Application to CSV Table
    		ADD_TO_LOG="$(echo -e ${PROJECT_NAME}),$(echo -e ${APP_ENV_NAME}),$(echo -e ${PORT_NUMBER})"
    		echo -e ${ADD_TO_LOG} >> $SUPERVISOR_LOG_FILE

        APP_LOCALHOST_SERVER="server 127.0.0.1:$(echo ${PORT_NUMBER});"
        echo -e $APP_LOCALHOST_SERVER
        sed -e "s|${APP_ENV_NAME} Port List|a ${APP_LOCALHOST_SERVER}" $NGINX_PROJECT_CONFIG > $NGINX_PROJECT_CONFIG.tmp && mv $NGINX_PROJECT_CONFIG.tmp $NGINX_PROJECT_CONFIG

    		# Increase itterater by 1
    		i=$[$i+1]
  	done

    printf "\nUpdated:\n$SUPERVISOR_LOG_FILE\n\n"
    unset PORT_NUMBER
  	echo -e "[group:$(echo -e ${APP_ENV_NAME})]" >> $SUPERVISOR_PROJECT_CONFIG
    echo -e "programs=$(echo -e $(join , "${APP_NAME_ARRAY[@]}"))"$'\n\n\n' >> $SUPERVISOR_PROJECT_CONFIG
  	# Unset APP_NAME_ARRAY to start over for next loop
  	unset APP_NAME_ARRAY
  	printf "Supervisor Settings added for $(echo -e ${APP_ENV_NAME}):\n$(echo -e ${SUPERVISOR_PROJECT_CONFIG})\n\n"


  	printf "Build of '$(echo -e ${APP_ENV_NAME})' Done.\n\n"
  done
done

# sudo nginx -t

exit
