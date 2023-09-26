import { Interface } from '@ethersproject/abi'
const axios = require('axios').default

async function errorDecode() {
  const permissionlessNodeRegistryJson = require('../artifacts/contracts/DVT/SSV/SSVNodeRegistry.sol/SSVNodeRegistry.json')
  let interfaces = new Interface(permissionlessNodeRegistryJson.abi)

  let error_msg = interfaces.getError('0x1adfa873')
  console.log('error is ', error_msg.name)
}

errorDecode()
