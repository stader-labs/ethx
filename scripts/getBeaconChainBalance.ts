export async function validatorBalaceQuery(pubKey: any) {
	try {
		const axios = require("axios").default;
		console.log("pubKey received ", pubKey);
		const balanceReq = `https://prater.beaconcha.in/api/v1/validator/${pubKey}/performance`;

		const responseObject = await axios.get(balanceReq);
		// console.log("response request ", responseObject);
		// console.log("response object data", responseObject.data);
		return responseObject.data.data.balance * 10**9; 

	} catch (e) {
		console.log("error while fetching validator balance ", e);
		return 32000000000000000000;
	}
}
