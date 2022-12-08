import { EthereumKeyStore, Encryption, Threshold } from "ssv-keys";

import { encode } from "js-base64";
import Web3 from "web3";



const web3 = new Web3();

export async function distributeKeys(
  keystore :any,
  keystorePassword :any,
  operators :any,
  operatorIndex :any
) {

  const operatorIds = [];
  const operatorKeys = [];
  const operatorsPublicKeys = [];
  const keyStore = new EthereumKeyStore(JSON.stringify(keystore));
  const privateKey = await keyStore.getPrivateKey(keystorePassword);

  for (const operator of operators[operatorIndex]) {
    operatorIds.push(operator.operatorId);
    operatorKeys.push(operator.operatorKey);
    operatorsPublicKeys.push(
      web3.eth.abi.encodeParameter("string", encode(operator.operatorKey))
    );
  }

  const thresholdInstance = new Threshold();
  const threshold = await thresholdInstance.create(privateKey, operatorIds);

  let shares = new Encryption(operatorKeys, threshold.shares).encrypt();

  shares = shares.map((share) => {
    share.operatorPublicKey = encode(share.operatorPublicKey);
    return share;
  });

  const sharePublicKeys = shares.map((share) => share.publicKey);

  const shareEncrypted = shares.map((share) =>
    web3.eth.abi.encodeParameter("string", share.privateKey)
  );

  return {
    pubKey: threshold.validatorPublicKey,
    publicShares: sharePublicKeys,
    encryptedShares: shareEncrypted,
    operatorIds: operatorIds,
    operatorsPublicKeys: operatorsPublicKeys,
  };
}
