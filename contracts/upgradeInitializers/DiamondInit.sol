// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

// Rollups-related dependencies
import {Phase} from "../interfaces/IRollups.sol";
import {LibRollups} from "../libraries/LibRollups.sol";
import {LibInput} from "../libraries/LibInput.sol";
import {LibValidatorManager} from "../libraries/LibValidatorManager.sol";
import {LibSERC20Portal} from "../libraries/LibSERC20Portal.sol";
import {ClaimsMaskLibrary} from "../ClaimsMaskLibrary.sol";
import {LibFeeManager} from "../libraries/LibFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Diamond-related dependencies
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IERC173} from "../interfaces/IERC173.sol"; // not in openzeppelin-contracts yet
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// Initializes the diamond contract
// EIP-2535 specifies that the `diamondCut` function takes two optional
// arguments: address _init and bytes calldata _calldata
// These arguments are used to execute an arbitrary function using delegatecall
// in order to set state variables in the diamond during deployment or an upgrade
// More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface
contract DiamondInit {
    using LibValidatorManager for LibValidatorManager.DiamondStorage;

    /// @notice initialize the Rollups contract
    /// @param _inputDuration duration of input accumulation phase in seconds
    /// @param _challengePeriod duration of challenge period in seconds
    /// @param _inputLog2Size size of the input drive in this machine
    /// @param _feePerClaim fee per claim to reward the validators
    /// @param _erc20ForFee the ERC-20 used as rewards for validators
    /// @param _feeManagerOwner fee manager owner address
    /// @param _validators initial validator set
    /// @param _erc20ForPortal ERC-20 contract address used by the portal
    /// @dev validators have to be unique, if the same validator is added twice
    ///      consensus will never be reached
    function init(
        // rollups init variables
        uint256 _inputDuration,
        uint256 _challengePeriod,
        // input init variables
        uint256 _inputLog2Size,
        // fee manager init variables
        uint256 _feePerClaim,
        address _erc20ForFee,
        address _feeManagerOwner,
        // validator manager init variables
        address payable[] memory _validators,
        // specific ERC-20 portal init variables
        address _erc20ForPortal
    ) external {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // initializing facets
        initInput(_inputLog2Size);
        initValidatorManager(_validators);
        initRollups(_inputDuration, _challengePeriod);
        initSERC20Portal(_erc20ForPortal);
        initFeeManager(_feePerClaim, _erc20ForFee, _feeManagerOwner);
    }

    /// @notice initalize the Input facet
    /// @param _inputLog2Size size of the input drive in this machine
    function initInput(uint256 _inputLog2Size) private {
        LibInput.DiamondStorage storage inputDS = LibInput.diamondStorage();

        require(
            _inputLog2Size >= 3 && _inputLog2Size <= 64,
            "Log of input size: [3,64]"
        );

        inputDS.inputDriveSize = (1 << _inputLog2Size);
    }

    /// @notice initialize the Validator Manager facet
    /// @param _validators initial validator set
    function initValidatorManager(address payable[] memory _validators)
        private
    {
        LibValidatorManager.DiamondStorage storage vmDS =
            LibValidatorManager.diamondStorage();

        uint256 maxNumValidators = _validators.length;

        require(maxNumValidators <= 8, "up to 8 validators");

        vmDS.validators = _validators;
        vmDS.maxNumValidators = maxNumValidators;

        // create a new ClaimsMask, with only the consensus goal set,
        //      according to the number of validators
        vmDS.claimsMask = ClaimsMaskLibrary.newClaimsMaskWithConsensusGoalSet(
            maxNumValidators
        );
    }

    /// @notice rollups contract initialized
    /// @param _inputDuration duration of input accumulation phase in seconds
    /// @param _challengePeriod duration of challenge period in seconds
    event RollupsInitialized(uint256 _inputDuration, uint256 _challengePeriod);

    /// @notice initialize the Rollups facet
    /// @param _inputDuration duration of input accumulation phase in seconds
    /// @param _challengePeriod duration of challenge period in seconds
    function initRollups(uint256 _inputDuration, uint256 _challengePeriod)
        private
    {
        LibRollups.DiamondStorage storage rollupsDS =
            LibRollups.diamondStorage();

        rollupsDS.inputDuration = uint32(_inputDuration);
        rollupsDS.challengePeriod = uint32(_challengePeriod);
        rollupsDS.inputAccumulationStart = uint32(block.timestamp);
        rollupsDS.currentPhase_int = uint32(Phase.InputAccumulation);

        emit RollupsInitialized(_inputDuration, _challengePeriod);
    }

    /// @notice initialize the specific ERC-20 portal
    /// @param _erc20ForPortal ERC-20 contract address used by the portal
    function initSERC20Portal(address _erc20ForPortal) private {
        LibSERC20Portal.DiamondStorage storage serc20DS =
            LibSERC20Portal.diamondStorage();

        serc20DS.erc20Contract = _erc20ForPortal;
    }

    /// @notice FeeManagerImpl contract initialized
    /// @param _feePerClaim fee per claim to reward the validators
    /// @param _erc20ForFee the ERC-20 used as rewards for validators
    /// @param _feeManagerOwner fee manager owner address
    event FeeManagerInitialized(
        uint256 _feePerClaim,
        address _erc20ForFee,
        address _feeManagerOwner
    );

    /// @notice initalize the Fee Manager facet
    /// @param _feePerClaim fee per claim to reward the validators
    /// @param _erc20ForFee the ERC-20 used as rewards for validators
    /// @param _feeManagerOwner fee manager owner address
    function initFeeManager(
        uint256 _feePerClaim,
        address _erc20ForFee,
        address _feeManagerOwner
    ) private {
        LibFeeManager.DiamondStorage storage feeManagerDS =
            LibFeeManager.diamondStorage();

        feeManagerDS.feePerClaim = _feePerClaim;
        feeManagerDS.token = IERC20(_erc20ForFee);
        feeManagerDS.owner = _feeManagerOwner;

        emit FeeManagerInitialized(
            _feePerClaim,
            _erc20ForFee,
            _feeManagerOwner
        );
    }
}
