import { ClusterScanner, NonceScanner } from 'ssv-scanner';

async function main() {
  // these parameters should be known in advance
  const params = {
    nodeUrl: process.env.PROVIDER_URL_INFURA ?? '', // this can be an Infura, or Alchemy node, necessary to query the blockchain
    contractAddress: process.env.SSV_NETWORK ?? '', // this is the address of SSV smart contract
    ownerAddress: process.env.SSV_NODE_REGISTRY ?? '', // this is the wallet address of the cluster owner
    operatorIds: [181,184,185,186], // this is a list of operator IDs chosen by the owner for their cluster
  }

  // ClusterScanner is initialized with the given parameters
  const clusterScanner = new ClusterScanner(params);
  // and when run, it returns the Cluster Snapshot
  const result = await clusterScanner.run(params.operatorIds);
  console.log(JSON.stringify({
    'block': result.payload.Block,
    'cluster snapshot': result.cluster,
    'cluster': Object.values(result.cluster)
  }, null, '  '));

  const nonceScanner = new NonceScanner(params);
  const nextNonce = await nonceScanner.run();
  console.log('Next Nonce:', nextNonce);
}

void main();