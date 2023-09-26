import { ethers } from 'hardhat'

async function main() {
  const staderOracle = process.env.STADER_ORACLE ?? ''
  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracleInstance = await staderOracleFactory.attach(staderOracle)

  interface WithdrawnValidatorsStruct {
    poolId: number
    reportingBlockNumber: number
    sortedPubkeys: string[]
  }

  const input: WithdrawnValidatorsStruct = {
    poolId: 3,
    reportingBlockNumber: 9748800,
    sortedPubkeys: [
      '0x8ffa518de86de59dd92a7559c1d19dfb92961e8954aa601fe30502aec61af7b55c544366c1ba78fe8e03cdc57d9fbb12'],
  }

  interface ValidatorVerification {
    poolId: number
    reportingBlockNumber: number
    sortedReadyToDepositPubkeys: string[]
    sortedFrontRunPubkeys: string[]
    sortedInvalidSignaturePubkeys: string[]
  }

  const input1: ValidatorVerification = {
    poolId: 3,
    reportingBlockNumber: 9727800,
    sortedReadyToDepositPubkeys: ['0x8ffa518de86de59dd92a7559c1d19dfb92961e8954aa601fe30502aec61af7b55c544366c1ba78fe8e03cdc57d9fbb12','0xa2fd2ba4f1d0166afb7120e8c63481ad2ecf00b898abe2558cd88a699a6cfb854455bd5cb3824078975bf13d8f9fb0ec','0x98badff3fc308773a59149b147cfee61e0c01be5518f292a3a9a2a0cdb60bc68fc3113a7530e7fa3b7618401e337e528'],
    sortedFrontRunPubkeys: [],
    sortedInvalidSignaturePubkeys: []
  }



  const addKeyTx = await staderOracleInstance.submitWithdrawnValidators(input)

  console.log('submitted oracle report')
}
main()
