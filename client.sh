# Desktop client. Uses multipass to spin up an Ubuntu VM to act as a jump server for logging into spot instance
# AWS CLI and necessary scripts are installed on the VM to enable dynamically calling for instance ID, instance DNS address etc..

install() {
    echo ''
    echo 'Installing.. The process will take a few mins'
    echo ''
    if [ "$1" == 'Darwin' ]; then
        brew update
        brew cask install multipass
        sleep 10
    elif [ "$1" == 'Linux' ]; then
        sudo snap install multipass --classic
        sleep 5
    fi
}

uninstall() {
    echo ''
    echo 'Removing existing installation...'
    echo ''
    if [ "$1" == 'Darwin' ]; then
        brew update
        brew cask uninstall multipass
        sleep 5
    elif [ "$1" == 'Linux' ]; then
        sudo snap remove multipass
        sleep 5
    fi
}

check_VM() {
    str=$(multipass ls --format csv | tail -1)
    _str=${str#*,}
    STATE=${_str%%,*}
    if [ "$STATE" != "Running" ]; then
        VM_NAME="${str%%,*}"
        OS=`uname`
        multipass start $VM_NAME
    fi
}

check_VM_status() {
        # Check if VM exists and is up/down. Start VM if it is down
        str=$(multipass ls --format csv | tail -1)
        if [[ $str == *"spot-jump"* ]]; then
           VM_NAME="${str%%,*}"
           if [[ $str == *"Running"* ]]; then
               echo $VM_NAME > /dev/null 2>&1
           elif [[ $str == *"Stopped"* ]]; then
               echo "VM was down. Wait a few secs for it to start"
               multipass start $VM_NAME
               echo $VM_NAME > /dev/null 2>&1
           else
               multipass stop $VM_NAME
               echo "VM in an unknown state. Please try again. If problem persists, reinstall by running client with --setup arg"
               echo ""
           fi
        else
           echo "No VM present. Re-run spot client with --setup arg"
           echo ""
        fi
}

start() {
    # Takes one argument, for name of VM (e.g. 'spot-jump-923')

    # Check if instance is up. If not, start it
    str=$(multipass exec $1 -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" "Name=instance-state-name,Values=running,stopped,stopping" --output=text --query="Reservations[*].Instances[*].State")
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
    S3_KEY="${_KEY#*=}"
    S3_SECRET="${_SECRET#*=}"

    _KEY=$(grep -A3 '# ATG2 AWS' "$KB_PATH$KEYFILE" | tail -1)
    _SECRET=$(grep -A4 '# ATG2 AWS' "$KB_PATH$KEYFILE" | tail -1)
    EC2_KEY="${_KEY#*=}"
    EC2_SECRET="${_SECRET#*=}"

    INST_ID=$(multipass exec $1 -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" "Name=instance-state-name,Values=running,stopped,stopping" --output=text --query="Reservations[*].Instances[*].InstanceId")
    if [ "$STATE" == stopped ]; then
        multipass exec $1 -- ./spotter/start.sh $INST_ID $S3_KEY $S3_SECRET $EC2_KEY $EC2_SECRET
        if [ $? -eq 1 ]; then
            echo ''
            echo 'Instance not yet ready to start. Please wait 1-2 more mins'
            exit 1
        fi
        IP_ADDR=$(multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)
        GRAFANA_KEYFILE='grafana_api_key'
        GRAFANA_KEY=$(cat $KB_PATH$GRAFANA_KEYFILE)
        IP_ADDR_INFLUXDB=http://$IP_ADDR:8086
        GRAFANA_URL='http://grafana.atgtrading.co:3000/api/datasources/1'
        curl -X PUT -H "Authorization: Bearer $GRAFANA_KEY" -d "name=InfluxDB (Backtesting)&url=$IP_ADDR_INFLUXDB&type=influxdb&access=proxy" $GRAFANA_URL > /dev/null 2>&1
    elif [ "$STATE" == stopping ]; then
        echo 'Instance not fully stopped. Please wait a couple minutes for it to completely shut down'
        exit 1
    elif [ "$STATE" == running ]; then
        echo 'Instance is running'
    fi

}


#
### Main ###
#

if [ "$1" == --setup ]; then

    # Install multipass if not already installed
    str=`command -v multipass`
    OS=`uname`
    if [ "$str" == '' ]; then
        install $OS
    else
        if [ "$OS" == 'Darwin' ]; then
            STATUS=$(brew cask outdated | grep multipass)
            if [ "$STATUS" == '' ]; then
                brew cask upgrade multipass
            fi
        elif [ "$OS" == 'Linux' ]; then
            sudo snap refresh multipass
        fi
        read -p 'The app is already installed on your PC. Do you want to reinstall it with the latest version? (Y/N) ' conf
        if [[ $conf == Y* ]] || [[ $conf == y* ]]; then
            uninstall $OS
            install $OS
        else
            echo 'Exiting program...'
            echo ''
            exit 1
        fi
    fi

    # Clean up any old VMs
    multipass stop --all
    multipass delete --all
    multipass purge

    # Launch new VM install AWS CLI, and download utility scripts from github
    RANGE=999
    num=$RANDOM
    let "num %= $RANGE"
    VM_NAME="spot-jump-"$num
    multipass launch --name $VM_NAME
    multipass exec $VM_NAME -- sudo apt update
    multipass exec $VM_NAME -- sudo apt install -y awscli

    # Install AWS CLI in VM
    KEYFILE='atg2_aws_cli.csv'
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

    PEMFILE='atg2_oregon.pem'
    cp $KB_PATH$PEMFILE _tmp.pem
#    STR="$KB_PATH$PEMFILE $VM_NAME:/home/ubuntu/$PEMFILE"
    STR="_tmp.pem $VM_NAME:/home/ubuntu/$PEMFILE"
    multipass transfer $STR
    rm _tmp.pem
    STR="$VM_NAME -- chmod 600 /home/ubuntu/$PEMFILE"
    multipass exec $STR

    multipass copy-files $VM_NAME:/home/ubuntu/spotter/client.sh spot_client.sh
    chmod +x spot_client.sh

    echo ''
    echo 'Client successfully set up. You can now log in to the spot instance (i.e. run client with --login arg)'
    echo ''

elif [ "$1" == --start ]; then
    check_VM_status VM_NAME

    start $VM_NAME

elif [ "$1" == --login ]; then
    check_VM_status VM_NAME

    start $VM_NAME

    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" "Name=instance-state-name,Values=running" --output=text --query="Reservations[*].Instances[*].InstanceId")
    multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --output=text --query "Reservations[*].Instances[*].PublicDnsName"
    echo 'SSHing into instance.. Type <exit> anytime to return to your regular shell'
    echo ''
    multipass exec $VM_NAME -- ./spotter/login.sh $INST_ID

elif [ "$1" == --stop ]; then
    read -p 'Please confirm before stopping the instance (Y/N) ' conf
    if [[ $conf == Y* ]] || [[ $conf == y* ]]; then
        echo ''
    else
        echo ''
        exit 1
    fi
    check_VM_status VM_NAME

    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" "Name=instance-state-name,Values=running" --output=text --query="Reservations[*].Instances[*].InstanceId")
    multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --output=text --query "Reservations[*].Instances[*].PublicDnsName"
    multipass exec $VM_NAME -- ./spotter/stop.sh $INST_ID

elif [ "$1" == --getaddr ]; then
    check_VM_status VM_NAME
    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" "Name=instance-state-name,Values=running" --output=text --query="Reservations[*].Instances[*].InstanceId")
    IP_ADDR=$(multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)
    echo 'Instance public DNS: '$IP_ADDR

elif [ "$1" == --status ]; then
    check_VM_status VM_NAME
    str=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" "Name=instance-state-name,Values=running,stopped,stopping" --output=text --query="Reservations[*].Instances[*].State")
    str=`echo $str | tr " " :`
    STATE=${str##*:}
    echo $STATE

elif [ "$1" == --update ]; then
    OS=`uname`
    if [ "$OS" == 'Darwin' ]; then
        KB_PATH='/Volumes/Keybase/team/atg_and_obt/'
    elif [ "$OS" == 'Linux' ]; then
        KB_PATH='/keybase/team/atg_and_obt/'
    else
        echo 'Unknown OS on your machine. Exiting'
        exit 1
    fi
    cp $KB_PATH/spot_client.sh .
    chmod 755 spot_client.sh

else
    echo ''
    echo 'Tool for managing spot instance. Run with the following args:'
    echo "    --setup    (Install app on your PC, or reinstall from scratch if already installed. Ie, './client --setup')"
    echo '    --start    (Start spot instance)'
    echo '    --login    (Login to spot instance shell. Will auto start instance if it is down)'
    echo '    --stop     (Stop spot instance)'
    echo '    --getaddr  (Get public DNS address of running instance)'
    echo '    --status   (Check if the instance is running/stopped/stopping)'
    echo '    --update   (Update client to the latest version)'
    echo ''
fi
