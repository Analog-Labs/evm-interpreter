// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {BranchlessMath} from "./BranchlessMath.sol";
import {Interpreter as InterpreterImpl} from "../src/Interpreter.sol";
import {Interpreter, InterpreterUtils} from "../src/utils/InterpreterUtils.sol";

contract InterpreterTest is Test {
    using BranchlessMath for uint256;
    using InterpreterUtils for Interpreter;

    address private constant CREATE2_DEPLOYER = address(0x0000000000001C4Bf962dF86e38F0c10c7972C6E);
    bytes32 private constant CREATE2_SALT = 0xc8530e31f6ca0170eadd291ef7444560d457094dc3888d929e3cd76bcd4acf7f;

    Interpreter internal immutable INTERPRETER;

    constructor() {
        address interpreter;
        bytes memory bytecode = type(InterpreterImpl).creationCode;
        vm.prank(CREATE2_DEPLOYER, CREATE2_DEPLOYER);
        assembly {
            interpreter := create2(0, add(bytecode, 0x20), mload(bytecode), CREATE2_SALT)
            if iszero(interpreter) { revert(0, 0) }
        }
        INTERPRETER = Interpreter.wrap(interpreter);
    }

    function encodePush(uint256 value) private pure returns (bytes memory data) {
        if (value == 0) {
            return hex"5f";
        }

        uint256 byteSize = (value.log2() + 8) >> 3;
        uint256 opcode = 0x5f + byteSize;
        data = new bytes(byteSize + 1);
        assembly {
            let bits := shl(3, byteSize)
            mstore8(add(data, 0x20), opcode)
            mstore(add(data, 0x21), shl(sub(256, bits), value))
        }
    }

    function test_opcodeAdd(uint256 a, uint256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(a), encodePush(b), hex"01", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );
        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a + b);
        }
    }

    function test_opcodeSub(uint256 a, uint256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(b), encodePush(a), hex"03", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );
        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a - b);
        }
    }

    function test_storage(bytes32 slot, bytes32 value) external {
        assertEq(INTERPRETER.sload(slot), bytes32(0));
        INTERPRETER.sstore(slot, value);
        assertEq(INTERPRETER.sload(slot), value);
    }
}
