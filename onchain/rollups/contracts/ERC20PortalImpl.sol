// Copyright 2021 Cartesi Pte. Ltd.

// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use
// this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

/// @title Generic ERC20 Portal Implementation
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ERC20Portal.sol";
import "./Input.sol";

contract ERC20PortalImpl is ERC20Portal {
    address immutable outputContract;
    Input immutable inputContract;

    modifier onlyOutputContract() {
        require(msg.sender == outputContract, "only outputContract");
        _;
    }

    constructor(address _inputContract, address _outputContract) {
        inputContract = Input(_inputContract);
        outputContract = _outputContract;
    }

    /// @notice deposit an amount of a generic ERC20 in the portal contract and create tokens in L2
    /// @param _ERC20 address of the ERC20 token contract
    /// @param _amount amount of the ERC20 token to be deposited
    /// @param _data information to be interpreted by L2
    /// @return hash of input generated by deposit
    function erc20Deposit(
        address _ERC20,
        uint256 _amount,
        bytes calldata _data
    ) public override returns (bytes32) {
        IERC20 token = IERC20(_ERC20);

        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "ERC20 transferFrom failed"
        );

        bytes memory input = abi.encode(msg.sender, _ERC20, _amount, _data);

        emit ERC20Deposited(_ERC20, msg.sender, _amount, _data);
        return inputContract.addInput(input);
    }

    /// @notice execute a rollups voucher
    /// @param _data data with information necessary to execute voucher
    /// @dev can only be called by the Output contract
    function executeRollupsVoucher(bytes calldata _data)
        public
        override
        onlyOutputContract
        returns (bool)
    {
        (address tokenAddr, address payable receiver, uint256 value) = abi
            .decode(_data, (address, address, uint256));

        IERC20 token = IERC20(tokenAddr);

        // transfer reverts on failure
        token.transfer(receiver, value);

        emit ERC20Withdrawn(tokenAddr, receiver, value);

        return true;
    }
}
