#!/bin/bash

#
# Shell script for green/blue deployment.
#
# Notes:
# - SED is assumed
# - JQ is assumed
# - UNIX target environment with SSH is assumed
#

CONFIG_FILE=$PWD'/deployer.config.json'
SCRIPT_LOCK=$PWD'/deployer.lock'
RUN_INSTALL=false

VERSION=1.0
DESCRIPTION='Tool used to implement zero downtime deployment.'

SCRIPT_NAME=$(basename "$0")

SED=$(which sed)
JQ=$(which jq)

# Color variables
GREEN=$'\033[1;32m'
BLUE=$'\033[1;34m'
NC=$'\033[0m'

# Check if lockfile exists
if [[ -e $SCRIPT_LOCK ]]; then

   # Output
   echo "$(tput setaf 1)Deploying already in progress.$(tput sgr 0)"

   # Terminate
   exit 0
fi

# Create lockfile
touch "$SCRIPT_LOCK"

# Listen for script termination
trap 'rm -f "$SCRIPT_LOCK"; exit $?' INT TERM EXIT

# Error handling and terminating
error()
{
   # Output
   echo "$(tput setaf 1)$1$(tput sgr 0)" >&2

   # Terminate
   exit 1
}

# Show help
help()
{
   # Output
   echo "$DESCRIPTION"
   echo
   echo "Syntax: $SCRIPT_NAME [-i|v|c|h]"
   echo "Options:"
   echo "c  Echo current color."
   echo "i  Run commands from 'commands.install' group immediately after prepare"
   echo "v  Print version."

   # Terminate
   # 
   exit 1
}

# Show version
version()
{
  # Output
  echo "$DESCRIPTION"
  echo "Version: $VERSION"

  # Terminate
  exit 1
}


# JSON processor needs to be installed
if ! [ -x "$(command -v jq)" ]; then

   # Output
   echo "$(tput setaf 1)supported JSON processor not found.$(tput sgr 0)"

   # Output
   echo 'Please download and install from https://stedolan.github.io/jq/'

   # Terminate
   exit 1
fi

# Deployment file not exists
if ! [ -f "$CONFIG_FILE" ]; then
   
   # Error
   error "Configuration not exists, please first create $CONFIG_FILE"
fi

# Get current deployment
CURRENT_COLOR=$( $JQ -r .current "$CONFIG_FILE" )

# Show current
current()
{
   # Output
   echo "Current deployed version: ${!CURRENT_COLOR}$(echo "$CURRENT_COLOR" | tr "[:lower:]" "[:upper:]")$NC"

   # Terminate
   exit 1
}


# Process input arguments
while getopts ":ivch" option; do
  case ${option} in
    i ) 
         # Use installation flag
         RUN_INSTALL=true

         # Output
         echo "$(tput setaf 3)Warning! $(tput sgr 0)Installation commands will be executed immediately after \"commands.prepare\""
      ;;
    v )  version
      ;;
    c )  current
      ;;
    h )  help
      ;;
    \? ) help
      ;;
  esac
done

# Get next deployment
NEXT_COLOR=$( [ "$CURRENT_COLOR" == 'blue' ] && echo 'green' || echo 'blue' )

# Current color uppercase
CC_UPPERCASE=$(echo "$CURRENT_COLOR" | tr '[:lower:]' '[:upper:]')

# Next color uppercase
NC_UPPERCASE=$(echo "$NEXT_COLOR" | tr '[:lower:]' '[:upper:]')

# Output
echo "$(tput setaf 3)Direction of deployment is $(tput sgr 0) ${!CC_UPPERCASE}$(echo "$CURRENT_COLOR" | tr "[:lower:]" "[:upper:]")$NC $(tput setaf 3)=>$(tput sgr 0) ${!NC_UPPERCASE}$(echo "$NEXT_COLOR" | tr "[:lower:]" "[:upper:]")$NC"

# Input
read -p "$(tput setaf 3)Are you sure? Start deployment (y/n)?$(tput sgr 0)" -n 1 -r

# Output
echo

# Terminate
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
   [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

# Check if logging is enabled
if [ $($JQ -r ".logging.enabled" "$CONFIG_FILE") = true ]
then

  # Close standard error descriptor

  # Write output to file
  exec 2> >( while read -r line; do

   # Output
   echo "[$(date +"%Y-%m-%d %T")] ${line}";

   done > $( $JQ -r .logging.file "$CONFIG_FILE" ) )
fi

# ------------------------------------------------------------------
# For real deployments, this is when you would update your project
# files in `$PWD/src/deployments/$NEXT_COLOR`, maybe via git pull.
# ------------------------------------------------------------------

# Output
echo "$(tput setaf 2)Running commands from \"commands.prepare\" $(tput sgr 0)"

# Change directory
cd "$NEXT_COLOR" || error "Error, directory \"$NEXT_COLOR\" not found"


# Running prepare commands
for k in $( $JQ -r '.commands.prepare | keys | .[]' "$CONFIG_FILE" ); do
    
   # Parse Command
   command=$( $JQ -r ".commands.prepare[$k]" "$CONFIG_FILE" );

   # Output
   echo "$(tput setaf 3)Running command $command $(tput sgr 0)"

   # Running deploy commands
   $command || error "Error, running command \"$command\" from \"commands.prepare\" failed"
done


# If running install commands option received
if $RUN_INSTALL ; then

   # Output
   echo "$(tput setaf 2)Running commands from \"commands.install\" $(tput sgr 0)"

   # Running install commands
   for k in $( $JQ -r '.commands.install | keys | .[]' "$CONFIG_FILE"); do
       
      # Parse Command
      command=$( $JQ -r ".commands.install[$k]" "$CONFIG_FILE" );

      # Output
      echo "$(tput setaf 3)Running command $command $(tput sgr 0)"

      # Running deploy commands
      $command || error "Error, running command \"$command\" from \"commands.install\" failed"
   done
fi

# Output
echo "$(tput setaf 2)Running commands from \"commands.build\" $(tput sgr 0)"

# Running build commands
for k in $( $JQ -r '.commands.build | keys | .[]' "$CONFIG_FILE" ); do
    
   # Parse Command
   command=$( $JQ -r ".commands.build[$k]" "$CONFIG_FILE" );

   # Output
   echo "$(tput setaf 3)Running command $command $(tput sgr 0)"

   # Running deploy commands
   $command || error "Error, running command \"$command\" from \"commands.install\" failed"
done

# Update current deployment
$JQ --arg a "${NEXT_COLOR}" '.current = $a' "$CONFIG_FILE" > "tmp" && mv "tmp" "$CONFIG_FILE"

# Output
echo "$(tput setaf 2)Running commands from \"commands.restart\" $(tput sgr 0)"

# Running restart deployment commands
for k in $( $JQ -r '.commands.restart | keys | .[]' "$CONFIG_FILE" ); do
    
   # Parse Command
   command=$( $JQ -r ".commands.restart[$k]" "$CONFIG_FILE" | $SED -e "s/#NEXT_COLOR#/$NEXT_COLOR/g;s/#CURRENT_COLOR#/$CURRENT_COLOR/g")

   # Output
   echo "$(tput setaf 3)Running command $command $(tput sgr 0)"

   # Running deploy commands
   $command || error "Error, running command \"$command\" from \"commands.restart\" failed"
done
