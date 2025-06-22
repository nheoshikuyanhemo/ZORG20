// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRouter {
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin,
        address to, uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, uint amountOutMin, address[] calldata path,
        address to, uint deadline
    ) external;
}

interface IBridgeOracle {
    function verifyMint(address to, uint256 amount, bytes calldata proof) external returns (bool);
}

contract ZORGToken {
    string public constant name = "Zero Organization";
    string public constant symbol = "ZORG";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    address public devWallet = 0xb50b87Cca4FD3cC57Bf253507aBF09cEDE3072a1;
    address public liquidityReceiver;

    uint256 public liquidityFee = 3; // 0.03%
    uint256 public devFee = 2;       // 0.02%
    uint256 public feeDenominator = 10000;

    address public routerAddress;
    address public WETH;
    IRouter public router;

    uint256 public swapThreshold = 10_000 * 1e18;
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    address public bridgeOracle;

    mapping(address => bool) public isFeeExempt;

    event OwnershipTransferred(address indexed previous, address indexed current);
    event BridgeMint(address indexed to, uint256 amount);
    event BridgeBurn(address indexed from, uint256 amount);

    constructor(address _router) {
        owner = msg.sender;
        routerAddress = _router;
        router = IRouter(_router);
        WETH = router.WETH();
        liquidityReceiver = msg.sender;

        totalSupply = 1_000_000_000 * 10 ** decimals;
        balanceOf[msg.sender] = totalSupply;

        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[devWallet] = true;

        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (shouldSwapBack() && !inSwap && from != routerAddress) {
            swapBack();
        }

        uint256 devAmt = 0;
        uint256 liqAmt = 0;
        if (!isFeeExempt[from] && !isFeeExempt[to]) {
            devAmt = (amount * devFee) / feeDenominator;
            liqAmt = (amount * liquidityFee) / feeDenominator;
        }

        uint256 finalAmt = amount - devAmt - liqAmt;

        balanceOf[from] -= amount;
        balanceOf[to] += finalAmt;
        balanceOf[address(this)] += devAmt + liqAmt;

        return true;
    }

    function shouldSwapBack() internal view returns (bool) {
        return balanceOf[address(this)] >= swapThreshold;
    }

    function swapBack() internal swapping {
        uint256 tokenAmount = balanceOf[address(this)];
        uint256 half = tokenAmount / 2;
        uint256 otherHalf = tokenAmount - half;

        address ;
        path[0] = address(this);
        path[1] = WETH;

        approveRouter(address(this), half);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half, 0, path, address(this), block.timestamp
        );

        uint256 ethBalance = address(this).balance;

        approveRouter(address(this), otherHalf);
        router.addLiquidityETH{value: ethBalance}(
            address(this), otherHalf, 0, 0, liquidityReceiver, block.timestamp
        );
    }

    function approveRouter(address _token, uint256 amount) internal {
        allowance[_token][routerAddress] = amount;
    }

    function setBridgeOracle(address _oracle) external onlyOwner {
        bridgeOracle = _oracle;
    }

    function mintBridge(address to, uint256 amount, bytes calldata proof) external {
        require(msg.sender == bridgeOracle, "Unauthorized");
        require(IBridgeOracle(bridgeOracle).verifyMint(to, amount, proof), "Invalid proof");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit BridgeMint(to, amount);
    }

    function burnBridge(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit BridgeBurn(msg.sender, amount);
    }

    function rescueZORG(uint256 amt) external onlyOwner {
        balanceOf[msg.sender] += amt;
        balanceOf[address(this)] -= amt;
    }

    function rescueNative() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    receive() external payable {}
}
