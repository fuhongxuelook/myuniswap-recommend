//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./ShibKingProInterface.sol";


contract Simdeal is Ownable {

    using SafeMath for uint256;

    address public pair;
    IUniswapV2Router02 public router;
    IUniswapV2Router02 public pancakeRouter;

    uint256 public totalFees = 13;

    uint256 directFee_buy = 4;
    uint256 indirectFee_buy = 2;

    uint256 directFee_sell = 2;
    uint256 indirectFee_sell = 1;

    uint DECIMAL_NUM = 10 ** 9;

    uint recommendOwnerSkpNum;

    mapping (address => bool) public automatedMarketMakerPairs;

    address private multiSigWallet = 0xb64D4270B8fe21e2704701Df9C8401fF110ecffD;

    constructor(address _router, address _pair, address _pancakeRouter) {
        router = IUniswapV2Router02(_router);
        pancakeRouter = IUniswapV2Router02(_pancakeRouter);
        pair = _pair;
        automatedMarketMakerPairs[pair] = true;
    }

    address public constant SKP = 0xCd79B84A0611971727928e1b7aEe9f8C61EDE777;
    address public USDT = 0x3813e82e6f7098b9583FC0F33a962D02018B6803;

    bool swapping;

    function dealSKP(address from, address to) public {
        uint256 amount = IERC20(SKP).balanceOf(address(this));

        bool fromIsExcludeFee = ShibKingProInterface(SKP).isExcludedFromFees(from);
        bool toIsExludeFee = ShibKingProInterface(SKP).isExcludedFromFees(to);
        
        bool takeFee = true;
        if(fromIsExcludeFee || toIsExludeFee) {
            takeFee = false;
        }

        if(takeFee && totalFees > 0) {
            uint recommendFee = 0;
            uint256 feesAmount = amount.mul(totalFees).div(100);
            if(automatedMarketMakerPairs[to]) {
                recommendFee = directFee_sell.add(indirectFee_sell);
            } else {
                recommendFee = directFee_buy.add(indirectFee_buy);
            }
            uint256 recommentAmount = feesAmount.mul(recommendFee).div(totalFees);
            if (!swapping && !automatedMarketMakerPairs[from]) {
                swapping = true;
                swapAndSendToUSDTForRecommend(from, recommentAmount);
                swapping =false;
            } else if (automatedMarketMakerPairs[from]){
                sendSKPToRecommend(to, recommentAmount, recommendFee);
            }

            amount = amount.sub(feesAmount);
            
        }
        // move to skp
        IERC20(SKP).transfer(SKP, amount);
    }

    function sendSKPToRecommend(address trader, uint _buyFeeAmount, uint _recommendFeeFee) private {
        if(_buyFeeAmount < 10000 * DECIMAL_NUM) {
            return;
        }

        address recommendRecipient = ShibKingProInterface(SKP).recommend(trader);
        address indirectRecommendRecipient = ShibKingProInterface(SKP).indirectRecommendation(trader) ;
        address _owner = ShibKingProInterface(SKP).owner();

        if (recommendRecipient == address(0)) {
            return;
        }

        if (IERC20(SKP).balanceOf(recommendRecipient) < 10_000_000 * DECIMAL_NUM) {
            return;
        }

        uint recommendBuyFeeAmount = _buyFeeAmount.mul(directFee_buy).div(_recommendFeeFee);
        uint indirectRecommendationAmount = _buyFeeAmount.sub(recommendBuyFeeAmount);

        if (recommendRecipient == _owner) {
            recommendOwnerSkpNum += recommendBuyFeeAmount;
        } else {
            IERC20(SKP).transfer(recommendRecipient, recommendBuyFeeAmount);
        }

        if (indirectRecommendRecipient == address(0)) {
            return;
        }

        if (IERC20(SKP).balanceOf(indirectRecommendRecipient) < 10_000_000 * DECIMAL_NUM) {
            return;
        }

        if (indirectRecommendRecipient == _owner) {
            recommendOwnerSkpNum += indirectRecommendationAmount;
        } else {
            IERC20(SKP).transfer(indirectRecommendRecipient, indirectRecommendationAmount);
        }
    }

    function swapAndSendToUSDTForRecommend(address trader, uint256 _amount) private {
        if (IERC20(SKP).balanceOf(address(this)) < _amount || _amount < 10_000 * DECIMAL_NUM) {
            return;
        }

        // save gas
        address recommendRecipient = ShibKingProInterface(SKP).recommend(trader);
        address indirectRecommendRecipient = ShibKingProInterface(SKP).indirectRecommendation(trader) ;
        address _owner = ShibKingProInterface(SKP).owner();

        if (recommendRecipient == address(0)) {
            return;
        }

        if (IERC20(SKP).balanceOf(recommendRecipient) < 10_000_000 * DECIMAL_NUM) {
            return;
        }

        bool hasIndeirect = true;

        if (indirectRecommendRecipient == address(0)) {
            hasIndeirect = false;
        }

        if (IERC20(SKP).balanceOf(indirectRecommendRecipient) < 10_000_000 * DECIMAL_NUM) {
            hasIndeirect = false;
        }

        if(recommendRecipient == _owner) {
            recommendRecipient = multiSigWallet;
        }

        if(indirectRecommendRecipient == _owner) {
            indirectRecommendRecipient = multiSigWallet;
        }

        uint256 usdtBal = IERC20(USDT).balanceOf(address(this));

        if(!hasIndeirect) {
            if(recommendRecipient == _owner) {
                return;
            }
            _amount = _amount.mul(2).div(3);
            swapTokensForUSDT(_amount);
            uint256 recommendUsdt = IERC20(USDT).balanceOf(address(this)).sub(usdtBal);
            if(recommendUsdt < 100) {
                return;
            }
            (bool b1, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", recommendRecipient, recommendUsdt));
            require(b1, "call error");
        } else {
            swapTokensForUSDT(_amount);
            uint256 uAmount = IERC20(USDT).balanceOf(address(this)).sub(usdtBal);
            if (uAmount < 100) {
                return;
            }
            uint recommendUsdt = uAmount.mul(2).div(3);
            uint indirectRecommendationAmount = uAmount.sub(recommendUsdt);
            (bool b1, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", recommendRecipient, recommendUsdt));
            require(b1, "call error");
            (bool b2, ) = USDT.call(
            abi.encodeWithSignature("transfer(address,uint256)", indirectRecommendRecipient, indirectRecommendationAmount));
            require(b2, "call error");
        }

    }


     function swapTokensForUSDT(uint256 tokenAmount) private {
        if(tokenAmount == 0) {
            return;
        }

        address[] memory path = new address[](3);
        path[0] = SKP;
        path[1] = pancakeRouter.WETH();
        path[2] = USDT;

        IERC20(SKP).approve(address(pancakeRouter), tokenAmount);

        // make the swap
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function setAutomatedMarketMakerPair(address _pair, bool value) public onlyOwner {
        automatedMarketMakerPairs[_pair] = value;
    }
}



