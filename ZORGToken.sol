// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ZORGToken {
    string public constant name = "Zero Organization";
    string public constant symbol = "ZORG";
    uint8 public constant decimals = 18;
    uint256 public totalSupply = 1_000_000_000 * 10 ** uint256(decimals);

    address public owner;
    address public devWallet = 0xb50b87Cca4FD3cC57Bf253507aBF09cEDE3072a1;

    uint256 public liquidityFee = 2; // 0.02%
    uint256 public devFee = 1;       // 0.01%
    uint256 public feeDenominator = 10000;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => bool) public isFeeExempt;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event BridgeBurn(address indexed from, uint256 amount);
    event BridgeMint(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = totalSupply;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;

        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        return _transfer(msg.sender, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        allowance[from][msg.sender] -= value;
        return _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 value) internal returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");

        uint256 devAmt = 0;
        uint256 liqAmt = 0;

        if (!isFeeExempt[from] && !isFeeExempt[to]) {
            devAmt = (value * devFee) / feeDenominator;
            liqAmt = (value * liquidityFee) / feeDenominator;
        }

        uint256 totalFee = devAmt + liqAmt;
        uint256 finalAmount = value - totalFee;

        balanceOf[from] -= value;
        balanceOf[to] += finalAmount;

        if (devAmt > 0) {
            balanceOf[devWallet] += devAmt;
            emit Transfer(from, devWallet, devAmt);
        }

        if (liqAmt > 0) {
            balanceOf[address(this)] += liqAmt;
            emit Transfer(from, address(this), liqAmt);
        }

        emit Transfer(from, to, finalAmount);
        return true;
    }

    // ========== OWNERSHIP & ADMIN ==========

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setFeeExempt(address addr, bool exempt) external onlyOwner {
        isFeeExempt[addr] = exempt;
    }

    // ========== RESCUE ==========

    function rescueZORG(uint256 amount) external onlyOwner {
        require(balanceOf[address(this)] >= amount, "Not enough");
        balanceOf[address(this)] -= amount;
        balanceOf[msg.sender] += amount;
        emit Transfer(address(this), msg.sender, amount);
    }

    function rescueNative() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    // ========== BRIDGE via RELAY.LINK ==========

    function burnForBridge(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit BridgeBurn(msg.sender, amount);
    }

    function mintFromBridge(address to, uint256 amount) external onlyOwner {
        // Callable by relay.link relay node after validation
        totalSupply += amount;
        balanceOf[to] += amount;
        emit BridgeMint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    receive() external payable {}
}
