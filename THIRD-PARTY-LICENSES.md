Compound Code (BSD-3-Clause License)
This project incorporates portions of code originally developed by Compound Labs, Inc. and 
licensed under the BSD-3-Clause License ("BSD-3-Clause"). The full text of the BSD-3-Clause 
License is included below for your reference:

Copyright (c) 2020 Compound Labs, Inc.
Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
 conditions and the following disclaimer.


2. Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials
  provided with the distribution.


3. Neither the name of the copyright holder nor the names of its contributors may be used
 to endorse or promote products derived from this software without specific prior written
  permission.


DISCLAIMER:

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The following sections of this project codebase are derived from the Compound code:
1. contracts/SDUtilityPool.sol -  accrueFee(), utilizerBalanceCurrent(address account), 
utilizerBalanceStored(address account), _utilizerBalanceStoredInternal(address account), 
exchangeRateCurrent(),exchangeRateStored(), _exchangeRateStored(). 
These are mainly the logic to compute the rewards, compute utilizer balance and
exchangeRate computation for cC-token based model.

Curvefi Code (MIT License)
This project incorporates portions of code originally developed by Ben Hauser and licensed
under the MIT License. The full text of the MIT License is included below for your reference:

MIT License

Copyright (c) 2020 Ben Hauser

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to
do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT
OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Specific Code Attribution:
The following sections of this project codebase are derived from the Curvefi code:
1. contracts/SDIncentiveController.sol - updateRewardForAccount(address account), 
rewardPerToken() and earned(address account).
These are mainly the logic for storing and computing user incentivize rewards.