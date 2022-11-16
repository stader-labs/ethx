import { ethers } from "hardhat";

async function main(){
    
    const staderSSVPool = process.env.STADER_SSV_STAKING_POOL ??'';
    const staderSSVPoolFactory = await ethers.getContractFactory("StaderSSVStakePool");
    const staderSSVPoolInstance = await staderSSVPoolFactory.attach(staderSSVPool);

    for (let i = 0; i < 5; i++) {
        const deposit = require(`./deposits/deposit${i}.json`);
        await staderSSVPoolInstance.depositEthToDepositContract(
            '0x'+deposit.pubkey,
            '0x'+deposit.withdrawal_credentials,
            '0x'+deposit.signature,
            '0x'+deposit.deposit_data_root
        );
    }
}

main();