import { Interface } from "@ethersproject/abi";
const axios = require('axios').default;


async function errorDecode(){

    const stakingContractJson = require('../artifacts/contracts/PermissionedPool.sol/PermissionedPool.json');
    let interfaces = new Interface(stakingContractJson.abi)

    let error_msg = interfaces.getError("0x481d7ab2");
    console.log("error is ", error_msg.name);

}

errorDecode();