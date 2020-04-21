# Desktop client. Uses multipass to spin up an Ubuntu VM to act as a jump server for logging into the server
# AWS CLI and necessary scripts are installed on the server to enable dynamically calling for instance ID, instance DNS address etc..

#
RANGE=999
num=$RANDOM
let "num %= $RANGE"
VM_NAME="spot-jump-"$num

if [ "$1" == --setup ]; then
    echo 'Installing.. The process will take 5-10 mins'
    echo ''

    # Install multipass if not already installed
    str=`command -v multipass`
    OS=`uname`
    if [ "$str" == '' ]; then
        if [ "$OS" == 'Darwin' ]; then
            brew update
            brew cask install multipass
            sleep 10
        elif [ "$OS" == 'Linux' ]; then
            sudo snap install multipass --classic
            sleep 5
        fi
    fi

    # Clean up any old VMs
    multipass stop --all
    multipass delete --all
    multipass purge

    # Launch new VM install AWS CLI, and download utility scripts from github
    multipass launch --name $VM_NAME
    multipass exec $VM_NAME -- sudo apt update
    multipass exec $VM_NAME -- sudo apt install -y awscli

    # Install AWS CLI in VM
    KEYFILE='atg_aws_cli.csv'
    if [ "$OS" == 'Darwin' ]; then
        KB_PATH='/Volumes/Keybase/team/atg_and_obt/'
    elif [ "$OS" == 'Linux' ]; then
        KB_PATH='/keybase/team/atg_and_obt/'
    fi
    CREDS=$(tail -1 $KB_PATH$KEYFILE)
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

    PEMFILE='atg_oregon.pem'
    STR="$KB_PATH$PEMFILE $VM_NAME:/home/ubuntu/$PEMFILE"
    multipass transfer $STR
    STR="$VM_NAME -- chmod 600 /home/ubuntu/$PEMFILE"
    multipass exec $STR
    echo ''
    echo 'Client successfully set up. You can now log in (i.e. run with --login arg)'

elif [ "$1" == --login ]; then
    str=$(multipass ls --format csv | tail -1)
    VM_NAME="${str%%,*}"

    # Check if instance is up. If not, start it
    str=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].State")
    str=`echo $str | tr " " :`
    STATE=${str##*:}

    OS=`uname`
    KEYFILE='keys.txt'
    if [ "$OS" == 'Darwin' ]; then
        KB_PATH='/Volumes/Keybase/team/atg_and_obt/'
    elif [ "$OS" == 'Linux' ]; then
        KB_PATH='/keybase/team/atg_and_obt/'
    fi
    _KEY=$(grep -A2 '# OBT AWS' "$KB_PATH$KEYFILE" | tail -1)
    _SECRET=$(grep -A3 '# OBT AWS' "$KB_PATH$KEYFILE" | tail -1)
    KEY="${_KEY#*=}"
    SECRET="${_SECRET#*=}"

    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].InstanceId")
    if [ "$STATE" == stopped ]; then
        echo 'Instance not currently running. Starting it.. May take 1-2 mins'
        multipass exec $VM_NAME -- ./spotter/start.sh $INST_ID $KEY $SECRET
    elif [ "$STATE" == stopping ]; then
        echo 'Instance not fully stopped. Please wait a couple minutes for it to completely shut down'
        exit 1
    fi

    multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --output=text --query "Reservations[*].Instances[*].PublicDnsName"
    echo 'SSHing into instance.. Type <exit> anytime to return to your regular shell'
    echo ''
    multipass exec $VM_NAME -- ./spotter/login.sh $INST_ID

elif [ "$1" == --stop ]; then
    str=$(multipass ls --format csv | tail -1)
    VM_NAME="${str%%,*}"

    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].InstanceId")
    multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --output=text --query "Reservations[*].Instances[*].PublicDnsName"
    multipass exec $VM_NAME -- ./spotter/stop.sh $INST_ID

elif [ "$1" == --getaddr ]; then
    str=$(multipass ls --format csv | tail -1)
    VM_NAME="${str%%,*}"
    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].InstanceId")
    IP_ADDR=$(multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)
    echo 'Public DNS: '$IP_ADDR

elif [ "$1" == --status ]; then
    str=$(multipass ls --format csv | tail -1)
    VM_NAME="${str%%,*}"
    str=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].State")
    str=`echo $str | tr " " :`
    STATE=${str##*:}
    echo $STATE

else
    echo 'This tool automates logins to spot instances that change over time'
    echo 'Run the script with the appropriate argument below. If this is your first time, use --setup:'
    echo "    --setup    (One-time initial setup, ie './client --setup')"
    echo '    --login    (Login to spot instance)'
    echo '    --stop     (Stop spot instance when you are finished with it)'
    echo '    --getaddr  (Get public DNS address of running instance)'
    echo '    --update   (Update to latest version of this client and supporting libraries. WORK IN PROGRESS)'
    echo '    --status   (Check if the instance is up/down)'
fi
