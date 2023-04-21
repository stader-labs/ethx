import { ethers } from 'hardhat'

async function main() {

    const permissionlessNodeRegistryFactory = await ethers.getContractFactory('PermissionlessNodeRegistry')
    const permissionlessNodeRegistryInstance = await permissionlessNodeRegistryFactory.attach('0x2f454143D26fB4E3C351c65B839AF8A64a1Fa1ea')

    let userTVL =0;
    let baseURL = 'https://goerli.beaconcha.in/api/v1/validator/'

    // const nexValidatorId = await permissionlessNodeRegistryInstance.nextValidatorId();

    for(let i=1;i<10 ;i++){
        const validator = await permissionlessNodeRegistryInstance.validatorRegistry(i);
        
        if(validator.status == 4){
            const response = await fetch(baseURL+validator.pubkey);
            const data = await response.json();
            console.log('response ', data)
            // userTVL += 
        }
    }
}

main()