// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRouter {
    function WPLUME() external pure returns (address);
    function addLiquidityETH(
        address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin,
        address to, uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract ZORGToken {
    string public name = "Zero Organization";
    string public symbol = "ZORG";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1_000_000_000 * 10 ** 18;

    address public owner;
    address public immutable devWallet = 0xb50b87Cca4FD3cC57Bf253507aBF09cEDE3072a1;
    address public constant ROUTER_ADDR = 0x35e44dc4702Fd51744001E248B49CBf9fcc51f0C;
    IRouter public constant router = IRouter(ROUTER_ADDR);
    address public immutable WPLUME;

    uint256 public constant liquidityFee = 3; // 0.03%
    uint256 public constant devFee = 2;       // 0.02%
    uint256 public constant burnFee = 1;      // 0.01%
    uint256 public constant feeDenominator = 10000;

    uint256 public maxWallet = (totalSupply * 2) / 100; // 2% limit

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromMaxWallet;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = totalSupply;
        WPLUME = router.WPLUME();

        isExcludedFromFee[msg.sender] = true;
        isExcludedFromMaxWallet[msg.sender] = true;

        emit Transfer(address(0), msg.sender, totalSupply);
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

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (!isExcludedFromMaxWallet[to]) {
            require(balanceOf[to] + amount <= maxWallet, "Exceeds max wallet");
        }

        if (isExcludedFromFee[from] || isExcludedFromFee[to]) {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
            return;
        }

        uint256 feeAmount = (amount * (liquidityFee + devFee + burnFee)) / feeDenominator;
        uint256 burnAmount = (amount * burnFee) / feeDenominator;
        uint256 net = amount - feeAmount;

        balanceOf[from] -= amount;
        balanceOf[to] += net;
        emit Transfer(from, to, net);

        balanceOf[address(this)] += (feeAmount - burnAmount);
        emit Transfer(from, address(this), feeAmount - burnAmount);

        balanceOf[address(0)] += burnAmount;
        emit Transfer(from, address(0), burnAmount);
    }

    // === Bridge Support ===
    function bridgeTransfer(address to, uint256 amount) external onlyOwner {
        require(balanceOf[address(this)] >= amount, "Insufficient bridge balance");
        balanceOf[address(this)] -= amount;
        balanceOf[to] += amount;
        emit Transfer(address(this), to, amount);
    }

    // === Rescue ===
    function rescueZORG(address to, uint256 amount) external onlyOwner {
        require(balanceOf[address(this)] >= amount, "Not enough");
        balanceOf[address(this)] -= amount;
        balanceOf[to] += amount;
        emit Transfer(address(this), to, amount);
    }

    function rescueNative(address to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Native rescue failed");
    }

    // === Owner Tools ===
    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }

    function setExcludedFromMaxWallet(address account, bool excluded) external onlyOwner {
        isExcludedFromMaxWallet[account] = excluded;
    }

    function setMaxWallet(uint256 newLimit) external onlyOwner {
        require(newLimit >= totalSupply / 100, "Must be >= 1%");
        maxWallet = newLimit;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    receive() external payable {}
}
