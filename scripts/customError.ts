import { Interface } from '@ethersproject/abi'
const axios = require('axios').default


async function errorDecode(){

    const stakingContractJson = require('../artifacts/contracts/PermissionedNodeRegistry.sol/PermissionedNodeRegistry.json');
    let interfaces = new Interface(stakingContractJson.abi)

    let error_msg = interfaces.getError("0xc4a3c169");
    console.log("error is ", error_msg.name);

}

errorDecode()
