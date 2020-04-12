# Desktop client. Uses multipass to spin up an Ubuntu VM to act as a jump server for logging into the server
# AWS CLI and necessary scripts are installed on the server to enable dynamically calling for instance ID, instance DNS address etc..

if [ -z "$1" ]
then
      VM_NAME="spot-jump"
else
      VM_NAME=$1
fi

multipass launch --name $VM_NAME

multipass exec $VM_NAME -- sudo apt update

multipass exec $VM_NAME -- sudo apt install -y awscli

CREDS=$(tail -1 /Volumes/Keybase/team/atg_and_obt/atg_aws_cli.csv)
rem=$CREDS
KEY="${rem%%,*}"; rem="${rem#*,}"
SECRET="${rem%%,*}"

touch _aws_creds_tmp
echo '[default]' >> _aws_creds_tmp
echo 'aws_access_key_id = '$KEY >> _aws_creds_tmp
echo 'aws_secret_access_key = '$SECRET >> _aws_creds_tmp
touch _aws_cfg_tmp
echo '[default]' >> _aws_cfg_tmp
echo 'region = us-west-2' >> _aws_cfg_tmp
echo 'output = json' >> _aws_cfg_tmp

multipass exec $VM_NAME -- mkdir /home/ubuntu/.aws
multipass exec $VM_NAME -- touch /home/ubuntu/.aws/credentials
multipass exec $VM_NAME -- touch /home/ubuntu/.aws/config
multipass transfer _aws_creds_tmp $VM_NAME:/home/ubuntu/.aws/credentials
multipass transfer _aws_cfg_tmp $VM_NAME:/home/ubuntu/.aws/config
rm _aws_creds_tmp
rm _aws_cfg_tmp

multipass exec $VM_NAME -- git clone https://github.com/sirdavealot/spotter.git

multipass exec $VM_NAME -- cd spotter

INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output text --query="Reservations[*].Instances[*].InstanceId")

multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text

multipass transfer /Volumes/Keybase/team/atg_and_obt/atg_oregon.pem $VM_NAME:/home/ubuntu/atg_oregon.pem
multipass exec $VM_NAME -- chmod 600 /home/ubuntu/atg_oregon.pem

multipass exec $VM_NAME -- ./spotter/login.sh $INST_ID
