#!/bin/bash

# set version (change if update is available)
glcoinVersion="29.2"


# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "glcoin.install.sh install - called by build.sdcard.sh"
  echo "Install or remove parallel chains for Glcoin Core:"
  echo "glcoin.install.sh install"
  echo "glcoin.install.sh [on|off] [signet|testnet|mainnet]"
  echo "Installs Glcoin Core $glcoinVersion by default"
  echo
  exit 1
fi

echo "# Running: glcoin.install.sh $*"

# mainnet | testnet | signet
CHAIN=${2:-mainnet}
if [ "${CHAIN}" != signet ] && [ "${CHAIN}" != testnet ] && [ "${CHAIN}" != mainnet ]; then
  echo "# ${CHAIN} is not supported"
  exit 1
fi
# prefixes for parallel services
if [ "${CHAIN}" = testnet ]; then
  prefix="t"
  glcoinprefix="test"
  zmqprefix=21 # zmqpubrawblock=21332 zmqpubrawtx=21333 zmqpubhashblock=21334
  rpcprefix=1  # rpcport=18332
elif [ ${CHAIN} = signet ]; then
  prefix="s"
  glcoinprefix="signet"
  zmqprefix=23
  rpcprefix=3
elif [ ${CHAIN} = mainnet ]; then
  prefix=""
  glcoinprefix="main"
  zmqprefix=28
  rpcprefix=""
fi
# glcoinlogpath
if [ ${CHAIN} = signet ]; then
  glcoinlogpath="/mnt/hdd/app-data/glcoin/signet/debug.log"
elif [ ${CHAIN} = testnet ]; then
  glcoinlogpath="/mnt/hdd/app-data/glcoin/testnet3/debug.log"
elif [ ${CHAIN} = mainnet ]; then
  glcoinlogpath="/mnt/hdd/app-data/glcoin/debug.log"
fi

function addGlcoinAliases {
  echo "# Add aliases ${prefix}glcoin-cli, ${prefix}glcoinlog"
  sudo -u admin touch /home/admin/_aliases
  if ! grep "alias ${prefix}glcoin-cli" /home/admin/_aliases; then
    echo "alias ${prefix}glcoin-cli=\"sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=${rpcprefix}8332\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias ${prefix}glcoinlog" /home/admin/_aliases; then
    echo "alias ${prefix}glcoinlog=\"sudo -u glcoin tail -n 30 -f ${glcoinlogpath}\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias glcoinconf" /home/admin/_aliases; then
    echo "alias glcoinconf=\"sudo nano /mnt/hdd/app-data/glcoin/glcoin.conf\"" |
      sudo tee -a /home/admin/_aliases
  fi
  sudo chown admin:admin /home/admin/_aliases
}

if [ "$1" = "install" ]; then
  echo "*** PREPARING GLCOIN ***"

  # prepare directories
  sudo rm -rf /home/admin/download
  sudo -u admin mkdir /home/admin/download
  cd /home/admin/download || exit 1

  echo "# Receive signer keys"
  curl -s "https://api.github.com/repos/glcoin-core/guix.sigs/contents/builder-keys" |
    jq -r '.[].download_url' | while read url; do curl -s "$url" | gpg --import; done

  # download signed binary sha256 hash sum file
  sudo -u admin wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS https://glcoincore.org/bin/glcoin-core-${glcoinVersion}/SHA256SUMS
  # download the signed binary sha256 hash sum file and check
  sudo -u admin wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS.asc https://glcoincore.org/bin/glcoin-core-${glcoinVersion}/SHA256SUMS.asc

  if gpg --verify SHA256SUMS.asc; then
    echo
    echo "*******************************************"
    echo "OK --> GLCOIN MANIFEST IS CORRECT"
    echo "*******************************************"
    echo
  else
    echo
    echo "# BUILD FAILED --> the PGP verification failed"
    exit 1
  fi

  # glcoinOSversion
  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    glcoinOSversion="arm-linux-gnueabihf"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    glcoinOSversion="aarch64-linux-gnu"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    glcoinOSversion="x86_64-linux-gnu"
  fi

  echo
  echo "*** GLCOIN CORE v${glcoinVersion} for ${glcoinOSversion} ***"

  # download resources
  binaryName="glcoin-${glcoinVersion}-${glcoinOSversion}.tar.gz"
  if [ ! -f "./${binaryName}" ]; then
    echo "# Downloading https://glcoincore.org/bin/glcoin-core-${glcoinVersion}/${binaryName} ..."
    sudo -u admin wget --quiet https://glcoincore.org/bin/glcoin-core-${glcoinVersion}/${binaryName}
  fi
  if [ ! -f "./${binaryName}" ]; then
    echo "# FAIL # Could not download the GLCOIN BINARY"
    exit 1
  else

    # check binary checksum test
    echo "- checksum test"
    # get the sha256 value for the corresponding platform from signed hash sum file
    glcoinSHA256=$(grep -i "${binaryName}" SHA256SUMS | cut -d " " -f1)
    binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
    echo "Valid SHA256 checksum should be: ${glcoinSHA256}"
    echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
    if [ "${binaryChecksum}" != "${glcoinSHA256}" ]; then
      echo "# FAIL # Downloaded GLCOIN BINARY not matching SHA256 checksum: ${glcoinSHA256}"
      rm -v ./${binaryName}
      exit 1
    else
      echo
      echo "*******************************************"
      echo "OK --> VERIFIED GLCOIN CORE BINARY CHECKSUM"
      echo "*******************************************"
      echo
      sleep 10
      echo
    fi
  fi

  # install
  sudo -u admin tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ glcoin-${glcoinVersion}/bin/*
  sudo install -m 0644 -o root -g root -D -t /usr/local/share/man/man1 glcoin-${glcoinVersion}/share/man/man1/*
  sleep 3
  if ! sudo /usr/local/bin/glcoind --version | grep "${glcoinVersion}"; then
    echo
    echo "# BUILD FAILED --> Was not able to install glcoind version(${glcoinVersion})"
    exit 1
  fi

  addGlcoinAliases

  echo "- Glcoin install OK"
  exit 0
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${prefix}glcoind.service" ]; then
    if [ ${CHAIN} != mainnet ]; then
      /usr/local/bin/glcoin-cli --${CHAIN} stop
    else
      /usr/local/bin/glcoin-cli stop
    fi
    sudo systemctl stop ${prefix}glcoind
    sudo systemctl disable ${prefix}glcoind
    sudo rm /etc/systemd/system/${prefix}glcoind.service 2>/dev/null
    if [ ${glcoinprefix} = signet ]; then
      # check for signet service set up by joinbox
      if [ -f "/etc/systemd/system/signetd.service" ]; then
        sudo systemctl stop signetd
        sudo systemctl disable signetd
        echo "# The signetd.service is stopped and disabled"
      fi
    fi
    echo "# Glcoin Core on ${CHAIN} service is stopped and disabled"
  fi
}

function installParallelService() {
  echo "# Installing Glcoin Core instance on ${CHAIN}"

  # make sure rpcbind is correctly configured
  sudo sed -i s/^rpcbind=/main.rpcbind=/g /mnt/hdd/app-data/glcoin/glcoin.conf
  if grep "rpcallowip" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    if ! grep "${glcoinprefix}.rpcbind=" /mnt/hdd/app-data/glcoin/glcoin.conf; then
      echo "${glcoinprefix}.rpcbind=127.0.0.1" |
        sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
    fi
  fi

  # correct rpcport entry
  sudo sed -i s/^rpcport=/main.rpcport=/g /mnt/hdd/app-data/glcoin/glcoin.conf
  if ! grep "${glcoinprefix}.rpcport" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "${glcoinprefix}.rpcport=${rpcprefix}8332" |
      sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
  fi

  # correct zmq entry
  sudo sed -i s/^zmqpubraw/main.zmqpubraw/g /mnt/hdd/app-data/glcoin/glcoin.conf
  if ! grep "${glcoinprefix}.zmqpubrawblock" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "\
${glcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
${glcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333" |
      sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
  fi

  # addnode
  if [ ${glcoinprefix} = signet ]; then
    if [ $(grep -c "${glcoinprefix}.addnode" </mnt/hdd/app-data/glcoin/glcoin.conf) -eq 0 ]; then
      echo "\
signet.addnode=s7fcvn5rble m7tiquhhr7acjdhu7wsawcph7ck44uxyd6sismumemcyd.onion:38333
signet.addnode=6megrs t422lxzsqvshkqkg6z2zhunywhy rhy3ltezaeyfspfyjdzr3qd.onion:38333
signet.addnode=jahtu4veqnvjldtbyxjiibdrltqiigha uai7hmvknwxhptsb4xat4qd.onion:38333
signet.addnode=f4kwoin7kk5a5kqpni7yqe25z66ckqu6bv37sqeluon24yne5rodzk qd.onion:38333
signet.addnode=nsgyo7begau4yecc46ljfecaykyzszcsea pxmtu6adrfagfrrznlngyd.onion:38333" |
        sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
    fi
  fi

  removeParallelService

  # /etc/systemd/system/${prefix}glcoind.service
  # based on https://github.com/glcoin/glcoin/blob/master/contrib/init/glcoind.service
  chainparameter=""
  if [ "${CHAIN}" != "mainnet" ]; then
    chainparameter="-${CHAIN}"
  fi
  echo "
[Unit]
Description=Glcoin daemon on ${CHAIN}

Wants=redis.service
After=redis.service

[Service]
Environment='MALLOC_ARENA_MAX=1'
ExecStartPre=-/home/admin/config.scripts/glcoin.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/glcoind ${chainparameter} \\
                                                  -daemonwait \\
                                                  -conf=/mnt/hdd/app-data/glcoin/glcoin.conf \\
                                                  -datadir=/mnt/hdd/app-storage/glcoin
PermissionsStartOnly=true

# Process management
######################
Type=forking
Restart=on-failure
TimeoutStartSec=infinity
TimeoutStopSec=600

# Directory creation and permissions
#####################################
# Run as glcoin:glcoin
User=glcoin
Group=glcoin

StandardOutput=null
StandardError=journal

# Hardening measures
#####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Deny access to /home, /root and /run/user
ProtectHome=true
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${prefix}glcoind.service
  sudo systemctl daemon-reload
  sudo systemctl enable ${prefix}glcoind
  echo "# OK - the glcoin daemon on ${CHAIN} service is now enabled"

  addGlcoinAliases

  source <(/home/admin/_cache.sh get state)

  if [ "${state}" == "ready" ]; then
    echo "# OK - the ${prefix}glcoind.service is enabled, system is ready so starting service"
    sudo systemctl start ${prefix}glcoind
  else
    echo "# OK - the ${prefix}glcoindservice is enabled, to start manually use:"
    echo "sudo systemctl start ${prefix}glcoind"
  fi

  isInstalled=$(systemctl status ${prefix}glcoind | grep -c active)
  if [ $isInstalled -gt 0 ]; then
    echo "# Installed $(sudo -u glcoin glcoind --version | grep version)"
    echo
    echo "# Monitor the ${prefix}glcoind with:"
    echo "# sudo tail -f /mnt/hdd/app-storage/glcoin/${prefix}debug.log"
    echo
  else
    echo "# Installation failed"
    echo "# See:"
    echo "# sudo journalctl -fu ${prefix}glcoind"
    exit 1
  fi
}

source /mnt/hdd/app-data/raspiblit z.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # make sure the glcoin directory is present and is linked
  echo "# Glcoin datadir"
  source <(sudo /home/admin/config.scripts/blitz.data.sh status)
  mkdir -p ${storageMountedPath}/app-storage/glcoin
  echo "# Liniking /glcoin"
  unlink /mnt/hdd/glcoin 2>/dev/null
  ln -s ${storageMountedPath}/app-storage/glcoin /mnt/hdd/glcoin
  chown -R glcoin:glcoin /mnt/hdd/glcoin
  chmod -R 777 /mnt/hdd/glcoin

  installParallelService
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${CHAIN} "on"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstall Glcoin Core instance on ${CHAIN}"
  removeParallelService
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${CHAIN} "off"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
