import { Interface } from "@ethersproject/abi";
const axios = require('axios').default;


async function errorDecode(){

    const stakingContractJson = require('../artifacts/contracts/StaderValidatorRegistry.sol/StaderValidatorRegistry.json');
    let interfaces = new Interface(stakingContractJson.abi)

    let error_msg = interfaces.getError("0xe92c469f");
    console.log("error is ", error_msg.name);

}

errorDecode();