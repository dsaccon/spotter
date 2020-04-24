# Pass in instance ID as first arg when running script

if [ -z "$1" ]
then
    echo "No arg passed in. You need to passed in one arg for instance-ID, eg './stop i-0c24488afbcf2dd2f'"
    exit 1
fi

export INST_ID=$1

aws ec2 stop-instances --instance-ids $INST_ID > /dev/null 2>&1

echo 'Instanced stopped'
