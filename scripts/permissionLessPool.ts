async function main() {
  const validatorRegistry = process.env.PERMISSION_LESS_POOL ?? ''
  const validatorRegistryFactory = await ethers.getContractFactory('StaderPermissionLessStakePool')
  const validatorRegistryInstance = await validatorRegistryFactory.attach(validatorRegistry)
  const porAddressList = await validatorRegistryInstance.updatedepositQueueStartIndex()
  console.log('added keys')
}
main()
