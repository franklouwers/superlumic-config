#!/bin/bash

BGreen='\e[1;32m'       # Green
BRed='\e[1;31m'         # Red
Color_Off='\e[0m'       # Text Reset

function setStatusMessage {
    printf "${IRed} --> ${BGreen}$1${Color_Off}\n" 1>&2
}

printf "${BGreen}   _________                         .__                .__        ${Color_Off}\n"
printf "${BGreen}  /   _____/__ ________   ___________|  |  __ __  _____ |__| ____  ${Color_Off}\n"
printf "${BGreen}  \_____  \|  |  \____ \_/ __ \_  __ \  | |  |  \/     \|  |/ ___\ ${Color_Off}\n"
printf "${BGreen}  /        \  |  /  |_> >  ___/|  | \/  |_|  |  /  Y Y  \  \  \___ ${Color_Off}\n"
printf "${BGreen} /_______  /____/|   __/ \___  >__|  |____/____/|__|_|  /__|\___  >${Color_Off}\n"
printf "${BGreen}         \/      |__|        \/ http://superlumic.com \/        \/ ${Color_Off}\n\n"

setStatusMessage "Checking if we need to ask for a sudo password"

sudo -v
export ANSIBLE_ASK_SUDO_PASS=True

repo=$1
username=$USER
if [ ! -z "$2" ]; then
    username=$2
fi

function triggerError {
    printf "${BRed} --> $1 ${Color_Off}\n" 1>&2
    exit 1
}

# Check whether a command exists - returns 0 if it does, 1 if it does not
function exists {
  if command -v $1 >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

# credits https://github.com/boxcutter/osx/blob/master/script/xcode-cli-tools.sh
function install_clt {
    # Get and install Xcode CLI tools
    OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')

    # on 10.9+, we can leverage SUS to get the latest CLI tools
    if [ "$OSX_VERS" -ge 9 ]; then
        # create the placeholder file that's checked by CLI updates' .dist code
        # in Apple's SUS catalog
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        # find the CLI Tools update
        PROD=$(softwareupdate -l | grep "\*.*Command Line" | head -n 1 | awk -F"*" '{print $2}' | sed -e 's/^ *//' | tr -d '\n')
        # install it
        softwareupdate -i "$PROD" -v
        rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    # on 10.7/10.8, we instead download from public download URLs, which can be found in
    # the dvtdownloadableindex:
    # https://devimages.apple.com.edgekey.net/downloads/xcode/simulators/index-3905972D-B609-49CE-8D06-51ADC78E07BC.dvtdownloadableindex
    else
        [ "$OSX_VERS" -eq 7 ] && DMGURL=http://devimages.apple.com.edgekey.net/downloads/xcode/command_line_tools_for_xcode_os_x_lion_april_2013.dmg
        [ "$OSX_VERS" -eq 7 ] && ALLOW_UNTRUSTED=-allowUntrusted
        [ "$OSX_VERS" -eq 8 ] && DMGURL=http://devimages.apple.com.edgekey.net/downloads/xcode/command_line_tools_for_osx_mountain_lion_april_2014.dmg

        TOOLS=clitools.dmg
        curl "$DMGURL" -o "$TOOLS"
        TMPMOUNT=`/usr/bin/mktemp -d /tmp/clitools.XXXX`
        hdiutil attach "$TOOLS" -mountpoint "$TMPMOUNT"
        installer $ALLOW_UNTRUSTED -pkg "$(find $TMPMOUNT -name '*.mpkg')" -target /
        hdiutil detach "$TMPMOUNT"
        rm -rf "$TMPMOUNT"
        rm "$TOOLS"
        exit
    fi
}

setStatusMessage "Keep-alive: update existing sudo time stamp until we are finished"

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

export HOMEBREW_CASK_OPTS="--appdir=/Applications"

if [[ ! -f "/Library/Developer/CommandLineTools/usr/bin/clang" ]]; then
    setStatusMessage "Install the CLT"
    install_clt
fi

# Install Ansible
if ! exists pip; then
    setStatusMessage "Install PIP"
    sudo easy_install --quiet pip
fi
if ! exists ansible; then
    setStatusMessage "Install Ansible"
    pip install --upgrade setuptools --user python
    sudo pip install -q ansible
fi

setStatusMessage "Create necessary folders"

sudo mkdir -p /usr/local/superlumic
sudo mkdir -p /usr/local/superlumic/roles
sudo chmod -R g+rwx /usr/local
sudo chgrp -R admin /usr/local

if [ -d "/usr/local/superlumic/config" ]; then
    setStatusMessage "Update your config from git"
    cd /usr/local/superlumic/config
    git pull -q
else
    if [ ! -z "$repo" ]; then
        setStatusMessage "Getting your config from your fork"
        git clone -q $1 /usr/local/superlumic/config
    else
        setStatusMessage "Getting the default config"
        git clone -q https://github.com/superlumic/superlumic-config.git /usr/local/superlumic/config
    fi
fi

cd /usr/local/superlumic

setStatusMessage "Create ansible.cfg"

{ echo '[defaults]'; echo 'roles_path=/usr/local/superlumic/roles:/usr/local/superlumic/config/roles'; } > ansible.cfg

setStatusMessage "Get all the required roles"

ansible-galaxy install -f -r config/requirements.yml -p roles

if [ -f "config/$username.yml" ]; then
    setStatusMessage "Running the ansible playbook for $username"
    ansible-playbook -i "localhost," config/$username.yml --ask-vault-pass
else
    if [ "travis" = "$username" ]; then
        setStatusMessage "Running the ansible playbook for $username but use roderik.yml as fallback"
        ansible-playbook -i "localhost," config/roderik.yml
    else
        triggerError "No playbook for $username found"
    fi
fi
