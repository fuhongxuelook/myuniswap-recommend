// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ShibKingProInterface {

	function isExcludedFromFees(address account) external view returns(bool);

	function recommend(address account) external view returns(address);

	function indirectRecommendation(address account) external view returns(address);

	function owner() external view returns (address);
}