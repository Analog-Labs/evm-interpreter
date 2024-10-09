## EVM Interpreter

**Optimized on-chain EVM interpreter, run arbitrary code without deploying a contract!**

This is an EVM-interpreter written in [pure EVM assembly](./src/interpreter.bytecode), each opcode executed using this interpreter has in average `~40 gas` overhead:

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
contract ProxyAccount {
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

## Usage

If you want to use this interpreter but has not mastered the black art of EVM assembly, you can use execute compile solidity code.


In this example, we will assume you deployed an [ProxyAccount](#account-abstraction) from the previous example, and now want to execute some arbitrary code.


### Method 01 - Fallback function

To Create a contract that contains the `fallback() external payable` method, executing the interpreter is equivalent to execute a contract constructor, you can't provide `calldata` parameters, so all the information must be available inside the bytecode itself (like executing a contract contructor).
```solidity
contract Method01 {
    IERC20 constant private USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    uint256 constant private ONE_DOLLAR = 1000000;

    fallback(bytes calldata) payable external returns (bytes memory) {
        // Transfer ETHER to 4 accounts
        payable(0x1E3187ff2b37e3587B94a21EAd1087357d0eeE10).transfer(0.1 ether);
        payable(0xd32Dac25bFF658A739E4ee26700Fb36aDf441607).transfer(0.1 ether);
        payable(0x0dAa76F786183a0820EC1Bb6b1f84015e8C7D453).transfer(0.1 ether);

        // Transfer USDT to 3 accounts
        USDT.transfer(0xc0B20370a21fc4ec94beeFd364F0E6C01a615ce8, ONE_DOLLAR);
        USDT.transfer(0xB8E766d71c3392144740c1c017667A5F8Ade7fE9, ONE_DOLLAR);
        USDT.transfer(0xf0289C6333BB1e9Dc80FA7a79A05371eFeC04a98, ONE_DOLLAR);
        
        // Verify final balance
        uint256 balance = USDT.balanceOf(address(this));
        return abi.encode(balance);
    }
}
```
When using the fallback function, you MUST use the contract `runtimeCode`, not the `creationCode`:

```solidity
type(Method01).runtimeCode  // <--- Must use this
type(Method01).creationCode // Not this
(bool success, bytes memory result) = INTERPRETER.delegatecall(type(Method01).runtimeCode);
uint256 balance = abi.decode(result, (uint256));
```

### Method 02 - Constructor function
The following code is equivalent to the previous one, except we use the constructor instead the fallback function, and this requires inline assembly to return the desired result.
One advantage of the constructor is that you can provide provide parameters (which are actually appended at the end of the bytecode).

tip: if you don't want to return any result, return empty bytes, because the solidity compiler will remove a lot of unecessary code.
```solidity
contract Method02 {
    IERC20 constant private USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    uint256 constant private ONE_DOLLAR = 1000000;

    constructor() {
        // Transfer ETHER to 4 accounts
        payable(0x1E3187ff2b37e3587B94a21EAd1087357d0eeE10).transfer(0.1 ether);
        payable(0xd32Dac25bFF658A739E4ee26700Fb36aDf441607).transfer(0.1 ether);
        payable(0x0dAa76F786183a0820EC1Bb6b1f84015e8C7D453).transfer(0.1 ether);

        // Transfer USDT to 3 accounts
        USDT.transfer(0xc0B20370a21fc4ec94beeFd364F0E6C01a615ce8, ONE_DOLLAR);
        USDT.transfer(0xB8E766d71c3392144740c1c017667A5F8Ade7fE9, ONE_DOLLAR);
        USDT.transfer(0xf0289C6333BB1e9Dc80FA7a79A05371eFeC04a98, ONE_DOLLAR);
        
        // Verify final balance
        uint256 balance = USDT.balanceOf(address(this));
        
        bytes memory result = abi.encode(balance);
        assembly {
            return(add(result, 0x20), mload(result))
        }
    }
}
```
When using the constructor, you MUST use the contract `creationCode`:

```solidity
type(Method02).creationCode // <--- Must use this
(bool success, bytes memory result) = INTERPRETER.delegatecall(type(Method02).creationCode);
uint256 balance = abi.decode(result, (uint256));
```

## Deployments [EVM Interpreter](./src/interpreter.bytecode)
The EVM Interpreter was permissionless deployed on all networks supported by the [Universal Factory](https://github.com/Lohann/universal-factory) at address `0x0000000000001e3F4F615cd5e20c681Cf7d85e8D`:

| NETWORK                                                                                                            | CHAIN ID |
|--------------------------------------------------------------------------------------------------------------------|:--------:|
| [**Ethereum Mainnet**](https://etherscan.io/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                    |     0    |
| [**Ethereum Classic**](https://etc.tokenview.io/en/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)             |    61    |
| [**Polygon PoS**](https://polygonscan.com/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                      |    137   |
| [**Arbitrum One**](https://arbiscan.io/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                         |   42161  |
| [**Avalanche C-Chain**](https://subnets.avax.network/c-chain/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)   |   43114  |
| [**BNB Smart Chain**](https://bscscan.com/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                      |    56    |
| [**Astar**](https://astar.blockscout.com/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                       |    592   |
| [**Sepolia**](https://sepolia.etherscan.io/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                     | 11155111 |
| [**Holesky**](https://holesky.etherscan.io/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                     |   17000  |
| [**Polygon Amoy**](https://amoy.polygonscan.com/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                |   80002  |
| [**Arbitrum One Sepolia**](https://sepolia.arbiscan.io/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)         |  421614  |
| [**Avalanche Fuji**](https://testnet.avascan.info/blockchain/c/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D) |   43113  |
| [**BNB Smart Chain Testnet**](https://testnet.bscscan.com/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)      |    97    |
| [**Moonbase**](https://moonbase.moonscan.io/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                    |   1287   |
| [**Shibuya**](https://shibuya.blockscout.com/address/0x0000000000001e3F4F615cd5e20c681Cf7d85e8D)                   |    81    |

## Known limitations
- The GAS opcode (a.k.a `gasleft()` in solidity) return different values between non-interpreted VS Interpreted code, this is due the interpreter overhead.
- No JUMPDEST table checks, to reduce the gas overhead this interpreter just check the PC points to JUMPDEST byte, it doesn't consider JUMPDEST inside a PUSH* for example.
- You cannot provide `CALLDATA` parameters (like when executing an contract constructor).

