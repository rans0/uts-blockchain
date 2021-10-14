ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/bakso.com/orderers/orderer1.bakso.com/msp/tlscacerts/tlsca.bakso.com-cert.pem
PEER1_ORG1_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/akang1.bakso.com/peers/peer1.akang1.bakso.com/tls/ca.crt
PEER1_ORG2_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/akang2.bakso.com/peers/peer1.akang2.bakso.com/tls/ca.crt

setGlobals() {
  PEER=$1
  AKANG=$2
  if [ $AKANG -eq 1 ]; then
    CORE_PEER_LOCALMSPID="Akang1MSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER1_ORG1_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/akang1.bakso.com/users/Admin@akang1.bakso.com/msp
    if [ $PEER -eq 1 ]; then
      CORE_PEER_ADDRESS=peer1.akang1.bakso.com:7051
    else
      CORE_PEER_ADDRESS=peer2.akang1.bakso.com:8051
    fi
  elif [ $AKANG -eq 2 ]; then
    CORE_PEER_LOCALMSPID="Akang2MSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER1_ORG2_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/akang2.bakso.com/users/Admin@akang2.bakso.com/msp
    if [ $PEER -eq 1 ]; then
      CORE_PEER_ADDRESS=peer1.akang2.bakso.com:9051
    else
      CORE_PEER_ADDRESS=peer2.akang2.bakso.com:10051
    fi
  fi
}

updateAnchorPeers() {
  PEER=$1
  AKANG=$2
  setGlobals $PEER $AKANG
  
  set -x
  peer channel update -o orderer1.bakso.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA
  set +x
  
  echo "===================== Anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME' ===================== "
  sleep $DELAY
  echo
}

joinChannelWithRetry() {
  PEER=$1
  AKANG=$2
  setGlobals $PEER $AKANG

  set -x
  peer channel join -b $CHANNEL_NAME.block
  res=$?
  set +x

  if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
    COUNTER=$(expr $COUNTER + 1)
    echo "peer${PEER}.org${AKANG} failed to join the channel, Retry after $DELAY seconds"
    sleep $DELAY
    joinChannelWithRetry $PEER $AKANG
  else
    COUNTER=1
  fi
}

installChaincode() {
  PEER=$1
  AKANG=$2
  setGlobals $PEER $AKANG
  
  set -x
  peer chaincode install -n mycc -l node -v 1.0 -p ${CC_SRC_PATH}
  set +x

  echo "===================== Chaincode is installed on peer${PEER}.org${AKANG} ===================== "
  echo
}

instantiateChaincode() {
  PEER=$1
  AKANG=$2
  setGlobals $PEER $AKANG

  set -x
  # peer chaincode instantiate -o orderer1.bakso.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -l node -v 1.0 -c '{"Args":["init","a", "100", "b","200"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')"
  peer chaincode instantiate -o orderer1.bakso.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -l node -v 1.0 -c '{"Args":["InitLedger"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')"
  # peer chaincode instantiate -o orderer1.bakso.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -l node -v 1.0 -c '{"Args":["SetOption", "ERC20 Token", "ERC20", "0"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')"
  set +x

  echo "===================== Chaincode is instantiated on peer${PEER}.org${AKANG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

chaincodeQuery() {
  PEER=$1
  AKANG=$2
  setGlobals $PEER $AKANG
  EXPECTED_RESULT=$3
  echo "===================== Querying on peer${PEER}.org${AKANG} on channel '$CHANNEL_NAME'... ===================== "
  local rc=1
  local starttime=$(date +%s)

  while
    test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
    sleep $DELAY
    echo "Attempting to Query peer${PEER}.org${AKANG} ...$(($(date +%s) - starttime)) secs"
    
    set -x
    peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["ReadAsset","asset1"]}' >&log.txt
    res=$?
    set +x
    
    test $rc -ne 0 && VALUE=$(cat log.txt)
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0; then
    echo "===================== Query successful on peer${PEER}.org${AKANG} on channel '$CHANNEL_NAME' ===================== "
  else
    echo "!!!!!!!!!!!!!!! Query result on peer${PEER}.org${AKANG} is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
    echo
    exit 1
  fi
}
