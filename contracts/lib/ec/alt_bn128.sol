// SPDX-License-Identifier: MIT
//
// From: https://gist.githubusercontent.com/chriseth/f9be9d9391efc5beb9704255a8e2989d/raw/4d0fb90847df1d4e04d507019031888df8372239/snarktest.solidity
// 
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

pragma solidity ^0.8.13;

struct G1Point {
	uint256 x;
	uint256 y;
}

// Encoding of field elements is: x[0] * z + x[1]
struct G2Point {
	uint256[2] x;
	uint256[2] y;
}

library PairingLib {
   	// p = p(u) = 36u^4 + 36u^3 + 24u^2 + 6u + 1
    uint256 public constant FIELD_ORDER = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;

    // Number of elements in the field (often called `q`)
    // n = n(u) = 36u^4 + 36u^3 + 18u^2 + 6u + 1
    uint256 public constant GEN_ORDER = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;

    uint256 public constant CURVE_B = 3;

    // a = (p+1) / 4
    uint256 public constant CURVE_A = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52;

	/// @return the generator of G1
	function P1() public pure returns (G1Point memory) {
		return G1Point(1, 2);
	}

	function HashToPoint(uint256 s) public view returns (G1Point memory) {
        uint256 beta = 0;
        uint256 y = 0;

        // XXX: Gen Order (n) or Field Order (p) ?
        uint256 x = s % GEN_ORDER;

        while( true ) {
            (beta, y) = FindYforX(x);

            // y^2 == beta
            if( beta == mulmod(y, y, FIELD_ORDER) ) {
                return G1Point(x, y);
            }

            x = addmod(x, 1, FIELD_ORDER);
		}

		revert();
    }


    /**
    * Given x, find y
    *
    *   where y = sqrt(x^3 + b)
    *
    * Returns: (x^3 + b), y
    */
    function FindYforX(uint256 x)
        public view returns (uint256, uint256)
    {
        // beta = (x^3 + b) % p
        uint256 beta = addmod(mulmod(mulmod(x, x, FIELD_ORDER), x, FIELD_ORDER), CURVE_B, FIELD_ORDER);

        // y^2 = x^3 + b
        // this acts like: y = sqrt(beta)
        uint256 y = expMod(beta, CURVE_A, FIELD_ORDER);

        return (beta, y);
    }


    // a - b = c;
    function submod(uint256 a, uint b) public pure returns (uint256){
        uint256 a_nn;

        if(a>b) {
            a_nn = a;
        } else {
            a_nn = a+GEN_ORDER;
        }

        return addmod(a_nn - b, 0, GEN_ORDER);
    }


    function expMod(uint256 _base, uint256 _exponent, uint256 _modulus)
        public view returns (uint256 retval)
    {
        bool success;
        uint256[1] memory output;
        uint256[6] memory input;
        input[0] = 0x20;        // baseLen = new(big.Int).SetBytes(getData(input, 0, 32))
        input[1] = 0x20;        // expLen  = new(big.Int).SetBytes(getData(input, 32, 32))
        input[2] = 0x20;        // modLen  = new(big.Int).SetBytes(getData(input, 64, 32))
        input[3] = _base;
        input[4] = _exponent;
        input[5] = _modulus;
        assembly {
            success := staticcall(sub(gas(), 2000), 5, input, 0xc0, output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success case 0 { invalid() }
        }
        require(success);
        return output[0];
    }


	/// @return the generator of G2
	function P2() public pure returns (G2Point memory) {
		return G2Point(
			[11559732032986387107991004021392285783925812861821192530917403151452391805634,
			 10857046999023057135944570762232829481370756359578518086990519993285655852781],
			[4082367875863433681332203403145435568316851327593401208105741076214120093531,
			 8495653923123431417604973247489272438418190587263600148770280649306958101930]
		);
	}

	/// @return the negation of p, i.e. p.add(p.negate()) should be zero.
	function g1neg(G1Point memory p) public pure returns (G1Point memory) {
		// The prime q in the base field F_q for G1
		uint256 q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
		if (p.x == 0 && p.y == 0)
			return G1Point(0, 0);
		return G1Point(p.x, q - (p.y % q));
	}

	/// @return the sum of two points of G1
	function g1add(G1Point memory p1, G1Point memory p2) public view returns (G1Point memory) {
		uint256[4] memory input;
		input[0] = p1.x;
		input[1] = p1.y;
		input[2] = p2.x;
		input[3] = p2.y;
		bool success;
		G1Point memory r;
		assembly {
			success := staticcall(150, 6, input, 0xc0, r, 0x60)
			// Use "invalid" to make gas estimation work
			switch success case 0 { invalid() }
		}
		require(success);
		return r;
	}

	/// @return the product of a point on G1 and a scalar, i.e.
	/// p == p.mul(1) and p.add(p) == p.mul(2) for all points p.
	function g1mul(G1Point memory p, uint256 s) public view returns (G1Point memory) {
		uint256[3] memory input;
		input[0] = p.x;
		input[1] = p.y;
		input[2] = s;
		bool success;
		G1Point memory r;
		assembly {
			success := staticcall(6000, 7, input, 0x80, r, 0x60)
			// Use "invalid" to make gas estimation work
			switch success case 0 { invalid() }
		}
		require (success);
    return r;
	}

	/// @return the result of computing the pairing check
	/// e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
	/// For example pairing([P1(), P1().negate()], [P2(), P2()]) should
	/// return true.
	function pairing(G1Point[] memory p1, G2Point[] memory p2) public view returns (bool) {
		require(p1.length == p2.length);
		uint256 inputSize = p1.length * 6;
		uint256[] memory input = new uint256[](inputSize);
		for (uint256 i = 0; i < p1.length; i++) {
			input[i * 6] = p1[i].x;
			input[i * 6 + 1] = p1[i].y;
			input[i * 6 + 2] = p2[i].x[0];
			input[i * 6 + 3] = p2[i].x[1];
			input[i * 6 + 4] = p2[i].y[0];
			input[i * 6 + 5] = p2[i].y[1];
		}
		uint256[1] memory out;
		bool success;
		assembly {
			success := staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
			// Use "invalid" to make gas estimation work
			switch success case 0 { invalid() }
		}
		require(success);
		return out[0] != 0;
	}
}
