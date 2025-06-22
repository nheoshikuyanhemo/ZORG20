// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ZORGToken {
    string public name = "Zero Organization";
    string public symbol = "ZORG";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1_000_000_000 * 10 ** uint256(decimals);

    address public owner;
    address public devWallet = 0xb50b87Cca4FD3cC57Bf253507aBF09cEDE3072a1;
    address public liquidityWallet = 0x35e44dc4702Fd51744001E248B49CBf9fcc51f0C;

    uint256 public devFee = 10; // 0.1%
    uint256 public liquidityFee = 10; // 0.1%
    uint256 public feeDenominator = 10000;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Allowance too low");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function setFees(uint256 _devFee, uint256 _liqFee) external onlyOwner {
        require(_devFee + _liqFee <= 100, "Fees too high");
        devFee = _devFee;
        liquidityFee = _liqFee;
    }

    function setDevWallet(address _wallet) external onlyOwner {
        devWallet = _wallet;
    }

    function setLiquidityWallet(address _wallet) external onlyOwner {
        liquidityWallet = _wallet;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "Insufficient balance");

        uint256 feeTotal = (amount * (devFee + liquidityFee)) / feeDenominator;
        uint256 feeDev = (amount * devFee) / feeDenominator;
        uint256 feeLiq = feeTotal - feeDev;
        uint256 sendAmount = amount - feeTotal;

        balanceOf[from] -= amount;
        balanceOf[to] += sendAmount;
        emit Transfer(from, to, sendAmount);

        if (feeDev > 0) {
            balanceOf[devWallet] += feeDev;
            emit Transfer(from, devWallet, feeDev);
        }

        if (feeLiq > 0) {
            balanceOf[liquidityWallet] += feeLiq;
            emit Transfer(from, liquidityWallet, feeLiq);
        }
    }
}
