// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * RWAProfitSharing — 平台收益 70% 按貢獻積分分配 (USDT)
 *
 * 與原始草稿相比，修正/強化：
 *  1. 修 BUG：原稿 updateContribution 誤用 Python 的 `def`，Solidity 必須是 `function`。
 *  2. 安全：原稿 distributeQuarterlyProfit 用 for 迴圈一次發給所有用戶，
 *     用戶一多就會 Out-of-Gas / 被惡意地址灌爆 (gas DoS)。
 *     → 改為「快照 + 用戶自行 claim」的 pull-payment 標準模式。
 *  3. 加入 ReentrancyGuard、SafeERC20 風格的回傳值檢查、owner 轉移。
 *
 * ⚠ 本合約供工程參考。正式上鏈前務必：第三方審計、加多簽 (multisig) 管理、
 *    並完成 STO/RWA 證券法規之合規程序。
 */

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract RWAProfitSharing {
    address public admin;
    IERC20  public usdtToken;

    // 防重入
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "REENTRANCY");
        _locked = 2;
        _;
        _locked = 1;
    }
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    // ---- 當期 (epoch) 積分快照 ----
    uint256 public currentEpoch;
    mapping(uint256 => uint256) public epochTotalPoints;            // epoch => 總積分
    mapping(uint256 => uint256) public epochPool;                   // epoch => 該期分配池 (70%)
    mapping(uint256 => mapping(address => uint256)) public points;  // epoch => user => 積分
    mapping(uint256 => mapping(address => bool))    public claimed; // epoch => user => 已領

    event ContributionUpdated(uint256 indexed epoch, address indexed user, uint256 points);
    event EpochFunded(uint256 indexed epoch, uint256 amount);
    event Claimed(uint256 indexed epoch, address indexed user, uint256 amount);
    event EpochClosed(uint256 indexed epoch, uint256 nextEpoch);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    constructor(address _usdtToken) {
        require(_usdtToken != address(0), "token=0");
        admin = msg.sender;
        usdtToken = IERC20(_usdtToken);
    }

    /// 後端依用戶行為 (回測貢獻、推廣等) 程序化設定當期積分
    function updateContribution(address _user, uint256 _points) external onlyAdmin {
        require(_user != address(0), "user=0");
        uint256 e = currentEpoch;
        uint256 prev = points[e][_user];
        epochTotalPoints[e] = epochTotalPoints[e] - prev + _points; // 增量更新總分
        points[e][_user] = _points;
        emit ContributionUpdated(e, _user, _points);
    }

    /// 注入當期的 70% 收益池 (admin 先 approve 本合約，再呼叫)
    function fundEpoch(uint256 amount) external onlyAdmin {
        require(amount > 0, "amount=0");
        require(usdtToken.transferFrom(msg.sender, address(this), amount), "fund transfer fail");
        epochPool[currentEpoch] += amount;
        emit EpochFunded(currentEpoch, amount);
    }

    /// 結算當期：鎖定快照並進入下一期 (避免邊發邊改)
    function closeEpoch() external onlyAdmin {
        uint256 closed = currentEpoch;
        currentEpoch += 1;
        emit EpochClosed(closed, currentEpoch);
    }

    /// 查詢某期可領金額
    function claimable(uint256 epoch, address user) public view returns (uint256) {
        if (claimed[epoch][user]) return 0;
        uint256 total = epochTotalPoints[epoch];
        if (total == 0) return 0;
        return (epochPool[epoch] * points[epoch][user]) / total;
    }

    /// 用戶自行領取 (pull-payment，無迴圈、無 gas DoS)
    function claim(uint256 epoch) external nonReentrant {
        require(epoch < currentEpoch, "epoch not closed");
        require(!claimed[epoch][msg.sender], "already claimed");
        uint256 amount = claimable(epoch, msg.sender);
        require(amount > 0, "nothing to claim");
        claimed[epoch][msg.sender] = true;                 // 先記帳，後轉帳 (checks-effects-interactions)
        require(usdtToken.transfer(msg.sender, amount), "transfer fail");
        emit Claimed(epoch, msg.sender, amount);
    }

    /// 轉移管理權 (正式環境建議改為多簽錢包地址)
    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "admin=0");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }
}
