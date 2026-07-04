# if there are more than 1 arguments check and see if the first one is a valid environment (dev, staging, prod)
if [ $# -gt 1 ] && [ "$1" = "dev" ] || [ "$1" = "uat" ] || [ "$1" = "prod" ]
then
    # set the environment variable
    export TF_WORKSPACE="$1"
    # remove the first argument
    shift
else   
    # raise an error that it requires an environment and exit
    echo "No environment set, please run again with prod as the environment argument"
    exit
fi

terraform "$@"