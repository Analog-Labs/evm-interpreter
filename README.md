## EVM Interpreter

**Optimized on-chain EVM interpreter, run arbitrary code without deploying a contract!**

This is an EVM-interpreter written in pure EVM assembly, this is useful for the following:

## Documentation

### Extract Contract Runtime Bytecode
Run the `type(Contract).creationCode` on-chain to extract the `type(Contract).runtimeCode`, useful when the contract has immutables.
<details>
  <summary>Example</summary>

  ```solidity
contract Example { ... }

contract ExtractRuntime {
    address constant internal INTERPRETER = 0x0000000000001e3F4F615cd5e20c681Cf7d85e8D;

    constructor() {
        // Because `Example` has immutables, `type(Example).runtimeCode` is not available.
        bytes memory initCode = type(Example).creationCode;
        
        // Execute the `initCode` without creating a new contract.
        (bool success, bytes memory runtimeCode) = interpreter.delegatecall(initCode);
        require(success);

        // Maybe modify the runtimeCode here
        assembly {
            // return the `Example` runtime code.
            return(add(runtimeCode, 0x20), mload(runtimeCode))
        }
    }
}
  ```
</details>

### Account Abstraction
Create a proxy account that delegates the call to the interpreter with additional ownership verification, and use it instead your EOA account!

<details>
  <summary>Example</summary>

  ```solidity
contract Account {
    address immutable private OWNER;
    address constant internal INTERPRETER = 0x0000000000001e3F4F615cd5e20c681Cf7d85e8D;

    constructor() {
        OWNER = msg.sender;
    }

    fallback() external payable {
        if (msg.sender != OWNER) {
            // Handle here `IERC721Receiver`, `ERC1155Receiver`, etc..
            return;
        }

        // Only the `OWNER` can execute arbitrary code.
        assembly {
            // copy the bytecode to memory
            calldatacopy(0, 0, calldatasize())
            
            // execute the interpreter with the provided bytecode.
            let success := delegatecall(
                gas(),
                INTERPRETER,
                0,
                calldatasize(),
                0,
                0
            )

            // copy the result to memory
            returndatacopy(0, 0, returndatasize())
            if success {
                return(0, returndatasize())
            }
            revert(0, returndatasize())
        }
    }
}
  ```
</details>

### EVM Introspection
Safely do introspection, such as checking wheter the EVM supports a given OPCODE, or measure the difference between actual gas used vs gas expected, etc.

<details>
  <summary>Example</summary>

  ```solidity
abstract contract ReentrancyGuard {
    address constant internal INTERPRETER = 0x0000000000001e3F4F615cd5e20c681Cf7d85e8D;

    /**
     * @dev reetrancy protection slot.
     * REENTRANCY_PROTECTION_SLOT = keccak256("reentrancy.protection");
     */
    bytes32 constant internal REENTRANCY_GUARD_SLOT = 0x687fec7eeab861a0be18a2f731f046a434b198fb814befbc577525895b895bc5;
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    // @dev Script that checks if the EVM supports EIP-1153 transient storage.
    //
    // 0x00 RETURNDATASIZE
    // 0x01 TLOAD          <--- this opcode will be invalid if the EVM doesn't support it.
    bytes constant internal SUPPORTS_EIP1155_SCRIPT = hex"3d5c";

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    /**
     * @dev Reads current reentracy guard value.
     */
    function _readGuard(bool supportsEip1153) private view returns (uint256 guard) {
        assembly {
            switch supportsEip1153
            case 0 {
                guard := tload(REENTRANCY_GUARD_SLOT)
            }
            default {
                guard := sload(REENTRANCY_GUARD_SLOT)
            }
        }
    }

    /**
     * @dev Set reentracy guard value.
     */
    function _setGuard(bool supportsEip1153, uint256 value) private {
        assembly {
            switch supportsEip1153
            case 0 {
                tstore(REENTRANCY_GUARD_SLOT, value)
            }
            default {
                sstore(REENTRANCY_GUARD_SLOT, value)
            }
        }
    }

    modifier nonReentrant() {
        // Dynamically check if this EVM supports EIP-1153
        // Obs: this adds an extra overhead for EVM's that doesn't support
        // EIP1153, but saves a lot of gas for those does.
        (bool supportsEip1153,) = INTERPRETER.staticcall{ gas: 300 }(SUPPORTS_EIP1155_SCRIPT);

        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_readGuard(supportsEip1153) == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Set Guard
        _setGuard(supportsEip1153, ENTERED);

        _;

        // Clear guard
        _setGuard(supportsEip1153, NOT_ENTERED);
    }

    function doSomething() external nonReentrant {
        // ...
    }
}
  ```
</details>

### Dynamic Contracts
Upgrade specific parts of a smart-contract, without having to deploy a new contract.

<details>
  <summary>Example</summary>

  ```solidity
contract Vault {
    address constant internal INTERPRETER = 0x0000000000001e3F4F615cd5e20c681Cf7d85e8D;

    // @notice Default authorization logic, checks if the sender is the `0xdeadbeef...` account.
    //
    //     0x00 CALLER
    //     0x01 PUSH20 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
    //     0x16 EQ
    //     0x17 PUSH1 0x1d
    // ,=< 0x19 JUMPI
    // |   0x1a RETURNDATASIZE
    // |   0x1b RETURNDATASIZE
    // |   0x1c REVERT
    // `=> 0x1d JUMPDEST
    bytes constant internal DEFAULT_AUTHORIZATION = hex"3373deadbeefdeadbeefdeadbeefdeadbeefdeadbeef14601d573d3dfd5b";

    /**
     * @dev Upgradeable authorization logic.
     */
    bytes authorizationLogic;

    constructor() {
        authorizationLogic = DEFAULT_AUTHORIZATION;
    }

    /**
     * Execute upgradeable logic for check if the sender is
     * authorized or not to perform this operation.
     */
    modifier _onlyAuthorized() {
        (bool authorized,) = INTERPRETER.delegatecall(authorizationLogic);
        require(authorized, "unauthorized");
        _;
    }

    function changeAuthorization(bytes memory newAuthorization) external _onlyAuthorized {
        authorizationLogic = newAuthorization;
    }

    function withdraw(uint256 amount, address recipient) external _onlyAuthorized {
        (bool success,) = payable(recipient).call{ gas: gasleft(), value: amount }("");
        require(success);
    }
}
  ```
</details>

## Deployments [EVM Interpreter](./src/UniversalFactory.sol)
The Universal Factory is already available in 8 blockchains and 7 testnets at address `0x0000000000001C4Bf962dF86e38F0c10c7972C6E`:

| NETWORK                                                                                                            | CHAIN ID |
|--------------------------------------------------------------------------------------------------------------------|:--------:|
| [**Ethereum Mainnet**](https://etherscan.io/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                    |     0    |
| [**Ethereum Classic**](https://etc.tokenview.io/en/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)             |    61    |
| [**Polygon PoS**](https://polygonscan.com/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                      |    137   |
| [**Arbitrum One**](https://arbiscan.io/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                         |   42161  |
| [**Avalanche C-Chain**](https://subnets.avax.network/c-chain/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)   |   43114  |
| [**BNB Smart Chain**](https://bscscan.com/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                      |    56    |
| [**Astar**](https://astar.blockscout.com/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                       |    592   |
| [**Sepolia**](https://sepolia.etherscan.io/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                     | 11155111 |
| [**Holesky**](https://holesky.etherscan.io/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                     |   17000  |
| [**Polygon Amoy**](https://amoy.polygonscan.com/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                |   80002  |
| [**Arbitrum One Sepolia**](https://sepolia.arbiscan.io/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)         |  421614  |
| [**Avalanche Fuji**](https://testnet.avascan.info/blockchain/c/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E) |   43113  |
| [**BNB Smart Chain Testnet**](https://testnet.bscscan.com/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)      |    97    |
| [**Moonbase**](https://moonbase.moonscan.io/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                    |   1287   |
| [**Shibuya**](https://shibuya.blockscout.com/address/0x0000000000001C4Bf962dF86e38F0c10c7972C6E)                   |    81    |
