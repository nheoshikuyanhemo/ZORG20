// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRouter {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, uint amountOutMin,
        address[] calldata path, address to, uint deadline
    ) external;

    function addLiquidityETH(
        address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin,
        address to, uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function WPLUME() external pure returns (address);
}

contract ZORGToken {
    string public name = "Zero Organization";
    string public symbol = "ZORG";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;
    address public constant devWallet = 0xb50b87Cca4FD3cC57Bf253507aBF09cEDE3072a1;
    address public constant ROUTER_ADDR = 0x35e44dc4702Fd51744001E248B49CBf9fcc51f0C;
    IRouter public router = IRouter(ROUTER_ADDR);
    address public immutable WPLUME;

    uint256 public constant devFee = 1;       // 0.01%
    uint256 public constant liquidityFee = 2; // 0.02%
    uint256 public constant feeDenominator = 10000;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isSniper;
    mapping(address => bool) public isExcludedFromFee;

    bool public inSwap;
    bool public autoLP = true;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SniperAdded(address indexed sniper);
    event SniperRemoved(address indexed sniper);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier notSniper(address addr) {
        require(!isSniper[addr], "Sniper blocked");
        _;
    }

    constructor() {
        owner = msg.sender;
        totalSupply = 1_000_000_000 * 10 ** decimals;
        balanceOf[msg.sender] = totalSupply;
        WPLUME = router.WPLUME();
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

    function _transfer(address from, address to, uint256 amount) internal notSniper(from) notSniper(to) {
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (isExcludedFromFee[from] || isExcludedFromFee[to] || inSwap) {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
            return;
        }

        uint256 feeAmount = (amount * (devFee + liquidityFee)) / feeDenominator;
        uint256 devPart = (amount * devFee) / feeDenominator;
        uint256 liqPart = feeAmount - devPart;
        uint256 netAmount = amount - feeAmount;

        balanceOf[from] -= amount;
        balanceOf[to] += netAmount;
        emit Transfer(from, to, netAmount);

        balanceOf[address(this)] += feeAmount;
        emit Transfer(from, address(this), feeAmount);

        if (!inSwap && to == ROUTER_ADDR && autoLP) {
            _swapAndLiquify();
        }
    }

    function _swapAndLiquify() internal swapping {
        uint256 tokenAmount = balanceOf[address(this)];
        if (tokenAmount == 0) return;

        uint256 half = tokenAmount / 2;
        uint256 otherHalf = tokenAmount - half;

        allowance[address(this)][address(router)] = tokenAmount;

        address ;
        path[0] = address(this);
        path[1] = WPLUME;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half, 0, path, address(this), block.timestamp
        );

        uint256 receivedPLUME = address(this).balance;

        if (receivedPLUME > 0) {
            router.addLiquidityETH{value: receivedPLUME}(
                address(this),
                otherHalf,
                0,
                0,
                owner,
                block.timestamp
            );
        }

        // Send dev fee in PLUME
        payable(devWallet).transfer((receivedPLUME * devFee) / (devFee + liquidityFee));
    }

    // === Management ===
    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }

    function setAutoLP(bool enabled) external onlyOwner {
        autoLP = enabled;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // === Anti-sniper ===
    function addSniper(address addr) external onlyOwner {
        isSniper[addr] = true;
        emit SniperAdded(addr);
    }

    function removeSniper(address addr) external onlyOwner {
        isSniper[addr] = false;
        emit SniperRemoved(addr);
    }

    // === Rescue ===
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(this), "Cannot rescue this token");
        (bool success, ) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(success, "Rescue failed");
    }

    function rescueNative(address to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Native rescue failed");
    }

    receive() external payable {}
}
