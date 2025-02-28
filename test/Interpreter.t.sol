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

    function encodeDup(uint256 depth) private pure returns (bytes memory data) {
        uint256 opcode = 0x7f + depth;
        data = new bytes(1);
        assembly {
            mstore8(add(data, 0x20), opcode)
        }
    }

    function encodeSwap(uint256 depth) private pure returns (bytes memory data) {
        uint256 opcode = 0x8f + depth;
        data = new bytes(1);
        assembly {
            mstore8(add(data, 0x20), opcode)
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

    function test_opcodePush() external view {
        uint256 a = 2;
        uint256 b = 1;

        bytes memory setToMem = bytes.concat(encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3");

        for (uint256 i = 0; i < 32; i++) {
            bytes memory pushba = bytes.concat(encodePush(b), encodePush(a));

            bytes memory data = bytes.concat(pushba, hex"03", setToMem);
            bytes memory result = INTERPRETER.call(data);

            unchecked {
                assertEq(abi.decode(result, (uint256)), a - b);
            }

            data = bytes.concat(pushba, hex"01", setToMem);
            result = INTERPRETER.call(data);

            unchecked {
                assertEq(abi.decode(result, (uint256)), a + b);
            }

            a = a << 8;
            b = b << 8;
        }
    }

    function test_opcodeDup(uint256 a) external view {
        bytes memory setToMem = bytes.concat(encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3");

        for (uint256 i = 1; i < 17; i++) {
            bytes memory pusha = encodePush(a);

            for (uint256 j = 0; j < i; j++) {
                uint256 b = a < j ? a : a - j;
                pusha = bytes.concat(pusha, encodePush(b));
            }

            bytes memory data = bytes.concat(pusha, encodeDup(i), setToMem);
            bytes memory result = INTERPRETER.call(data);

            unchecked {
                assertEq(abi.decode(result, (uint256)), a);
            }
        }
    }

    function test_opcodeSwap(uint256 a) external view {
        bytes memory setToMem = bytes.concat(encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3");

        for (uint256 i = 1; i < 17; i++) {
            bytes memory pusha = encodePush(a);

            for (uint256 j = 0; j < i; j++) {
                uint256 b = a < j ? a : a - j;
                pusha = bytes.concat(pusha, encodePush(b));
            }

            bytes memory data = bytes.concat(pusha, encodeSwap(i), setToMem);
            bytes memory result = INTERPRETER.call(data);

            unchecked {
                assertEq(abi.decode(result, (uint256)), a);
            }
        }
    }

    function test_opcodeSdiv(int256 a, int256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(uint256(b)),
            encodePush(uint256(a)),
            hex"05",
            encodePush(0),
            hex"52",
            encodePush(32),
            encodePush(0),
            hex"f3"
        );
        bytes memory result = INTERPRETER.call(data);
        uint256 d;
        assembly {
            d := sdiv(a, b)
        }

        unchecked {
            assertEq(abi.decode(result, (uint256)), d);
        }
    }

    function test_opcodeDiv(uint256 a, uint256 b) external view {
        if (b == 0) {
            return;
        }
        bytes memory data = bytes.concat(
            encodePush(uint256(b)),
            encodePush(uint256(a)),
            hex"04",
            encodePush(0),
            hex"52",
            encodePush(32),
            encodePush(0),
            hex"f3"
        );
        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a / b);
        }
    }

    function test_opcodeInvalidReverted() external {
        vm.expectRevert();
        bytes memory data = hex"21";
        INTERPRETER.call(data);
    }

    function test_opcodeEmptyReverted() external {
        vm.expectRevert();
        bytes memory data = bytes.concat(hex"A5", encodePush(32), encodePush(0), hex"f3");
        INTERPRETER.call(data);
    }

    function test_opcodeAnd(uint256 a, uint256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(a), encodePush(b), hex"16", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );

        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a & b);
        }
    }

    function test_opcodeLt(uint256 a, uint256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(a), encodePush(b), hex"10", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );

        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (bool)), b < a);
        }
    }

    function test_opcodeGt(uint256 a, uint256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(a), encodePush(b), hex"11", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );

        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (bool)), b > a);
        }
    }

    function test_opcodeShr(uint256 a, uint8 b) external view {
        bytes memory data = bytes.concat(
            encodePush(a), encodePush(b), hex"1C", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );

        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a >> b);
        }
    }

    function test_opcodeEq(uint256 a, uint256 b) external view {
        bytes memory data = bytes.concat(
            encodePush(a), encodePush(b), hex"14", encodePush(0), hex"52", encodePush(32), encodePush(0), hex"f3"
        );

        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (bool)), b == a);
        }
    }

    function test_opcodeJump(uint8 a) external view {
        if (a == 0) {
            a++;
        }

        bytes memory data = bytes.concat(encodePush(a), hex"60075660115b5f5260205ff3");
        console.logBytes(data);
        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a);
        }
    }

    function test_opcodeJumpAndJumpi(uint8 a) external view {
        if (a == 0) {
            a++;
        }

        bytes memory data =
            bytes.concat(encodePush(0x10), encodePush(a), hex"5b601014601257601160106004565b5f5260205ff3");
        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a == 0x10 ? 0x10 : 0x11);
        }
    }

    function test_opcodeJumpi(uint8 a) external view {
        if (a == 0) {
            a++;
        }

        bytes memory data = bytes.concat(encodePush(0x10), encodePush(a), hex"600114600c5760115b5f5260205ff3");
        console.logBytes(data);
        bytes memory result = INTERPRETER.call(data);
        unchecked {
            assertEq(abi.decode(result, (uint256)), a == 0x01 ? 0x10 : 0x11);
        }
    }

    function gcd(uint256 a, uint256 b) private pure returns (uint256) {
        while (b != 0) {
            uint256 t = b;
            b = a % b;
            a = t;
        }

        return a;
    }

    /// @notice GCD Naive implementation
    /// @dev
    /// PUSHN a
    /// PUSHN b
    /// JUMPDEST
    /// DUP1
    /// ISZERO
    /// PUSH1 0x10
    /// JUMPI
    /// DUP1
    /// SWAP2
    /// MOD
    /// PUSH1 0x04
    /// JUMP
    /// JUMPDEST
    /// SWAP1
    /// PUSH0
    /// MSTORE
    /// PUSH1 0x20
    /// PUSH0
    /// RETURN
    function test_gcd() external view {
        assertEq(gcd(2, 4), 2);
        assertEq(gcd(6, 14), 2);
        assertEq(gcd(1, 5), 1);

        uint256[3] memory a = [uint256(2), 6, 1];
        uint256[3] memory b = [uint256(4), 14, 5];

        for (uint256 i = 0; i < a.length; i++) {
            bytes memory data =
                bytes.concat(encodePush(a[i]), encodePush(b[i]), hex"5b80156010578091066004565b905f5260205ff3");

            bytes memory result = INTERPRETER.call(data);

            unchecked {
                assertEq(abi.decode(result, (uint256)), gcd(a[i], b[i]));
            }
        }
    }

    /// @notice Returns the index of least significant bit
    /// @param x the value for which to compute the most significant bit
    /// @return r the index of least significant bit from 0 to 255
    function binarySearchLsb(uint256 x) private pure returns (uint8 r) {
        r = 255;
        uint256 mask = 0xffffffffffffffffffffffffffffffff;
        uint8 k = 128;

        for (uint256 i = 0; i < 8; i++) {
            if (x & mask > 0) {
                r -= k;
            } else {
                x >>= k;
            }

            k /= 2;
            mask >>= k;
        }
    }

    /// @dev
    /// PUSH1 0xa1
    /// PUSH1 0xff
    /// PUSH1 0x80
    /// PUSH16 0xffffffffffffffffffffffffffffffff
    /// JUMPDEST
    /// DUP1
    /// DUP5
    /// AND
    /// PUSH0
    /// LT
    /// PUSH1 0x28
    /// JUMPI
    /// SWAP3
    /// DUP2
    /// SHR
    /// SWAP3
    /// SWAP2
    /// PUSH1 0x2d
    /// JUMP
    /// JUMPDEST
    /// DUP2
    /// SWAP1
    /// SWAP3
    /// SUB
    /// JUMPDEST
    /// SWAP1
    /// PUSH1 0x02
    /// SWAP1
    /// DIV
    /// DUP1
    /// SWAP3
    /// SWAP1
    /// SHR
    /// SWAP1
    /// SWAP2
    /// SWAP1
    /// DUP2
    /// PUSH0
    /// LT
    /// PUSH1 0x17
    /// JUMPI
    /// SWAP2
    /// PUSH0
    /// MSTORE
    /// PUSH0
    /// PUSH1 0x20
    /// RETURN
    function test_binarySearchLsb() external view {
        for (uint8 i = 0; i < 8; i++) {
            uint256 a = 1 << i;

            bytes memory data = bytes.concat(
                encodePush(a),
                hex"60ff60806fffffffffffffffffffffffffffffffff5b8084165f1060285792811c9291602d565b819092035b90600290048092901c909190815f10601757915f5260205ff3"
            );

            bytes memory result = INTERPRETER.call(data);

            unchecked {
                assertEq(abi.decode(result, (uint256)), binarySearchLsb(a));
            }
        }
    }

    function test_storage(bytes32 slot, bytes32 value) external {
        assertEq(INTERPRETER.sload(slot), bytes32(0));
        INTERPRETER.sstore(slot, value);
        assertEq(INTERPRETER.sload(slot), value);
    }
}
